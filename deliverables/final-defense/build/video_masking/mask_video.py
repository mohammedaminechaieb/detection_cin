"""Masque les zones de texte de la CIN dans la vidéo de démonstration.

Pour chaque image : détection des quadrilatères candidats, identification
(recto/verso, rotation) par corrélation avec les références redressées,
puis projection de rectangles blancs sur les zones de texte.
"""
import json
import subprocess
import sys

import cv2
import numpy as np

from regions import REGIONS

SRC, OUT, LOG = sys.argv[1], sys.argv[2], sys.argv[3]
CW, CH = 856, 540
SW, SHh = 214, 135          # taille de comparaison
R0 = CW / CH
SCALE = 0.5                 # détection en demi-résolution
PERSIST = 10                # images de persistance d'un masque perdu
ACCEPT = 0.42               # seuil de corrélation

def prep(img):
    g = cv2.GaussianBlur(img, (3, 3), 0).astype(np.float32)
    return g

refs = {}
for n in ("recto", "verso"):
    r = cv2.cvtColor(cv2.imread(f"ref_{n}.png"), cv2.COLOR_BGR2GRAY)
    refs[n] = prep(cv2.resize(r, (SW, SHh), interpolation=cv2.INTER_AREA))

CANON_SMALL = np.float32([[0, 0], [SW, 0], [SW, SHh], [0, SHh]])
CANON = np.float32([[0, 0], [CW, 0], [CW, CH], [0, CH]])


def ncc(a, b, m, min_valid=0.35):
    if m.sum() < min_valid * m.size:
        return -1
    a = a[m]; b = b[m]
    a = a - a.mean(); b = b - b.mean()
    d = np.sqrt((a * a).sum() * (b * b).sum())
    return float((a * b).sum() / d) if d > 0 else -1


def order(pts):
    pts = np.asarray(pts, np.float32)
    s = pts.sum(1); d = np.diff(pts, axis=1).ravel()
    return np.float32([pts[s.argmin()], pts[d.argmin()], pts[s.argmax()], pts[d.argmax()]])


def candidates(gray):
    h, w = gray.shape
    out = []
    masks = []
    for t in (70, 110, 150):
        masks.append(cv2.threshold(gray, t, 255, cv2.THRESH_BINARY)[1])
    masks.append(cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)[1])
    e = cv2.Canny(cv2.GaussianBlur(gray, (5, 5), 0), 30, 90)
    masks.append(cv2.morphologyEx(cv2.dilate(e, np.ones((3, 3), np.uint8)), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)))
    for m in masks:
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        cs, _ = cv2.findContours(m, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
        for c in cs:
            a = cv2.contourArea(c)
            if a < 900 or a > 0.9 * w * h:
                continue
            rect = cv2.minAreaRect(c)
            (rw, rh) = rect[1]
            if min(rw, rh) < 18:
                continue
            box = order(cv2.boxPoints(rect))
            if a / (rw * rh + 1e-6) < 0.6:
                continue
            out.append(box)
            x, y, bw, bh = cv2.boundingRect(c)
            # carte coupée par le haut ou le bas de l'écran (défilement)
            angle_ok = abs(((rect[2] + 45) % 90) - 45) < 3
            if angle_ok and (y <= 0.06 * h or y + bh >= 0.94 * h) and bw > 0.5 * w:
                for full_h in (bw / R0, bw * R0):
                    if full_h <= bh * 1.05:
                        continue
                    for y0 in (y + bh - full_h, y):
                        out.append(np.float32([[x, y0], [x + bw, y0], [x + bw, y0 + full_h], [x, y0 + full_h]]))
    return out


def hypotheses(box):
    # les 4 rotations : coin de la carte « haut-gauche » sur chacun des 4 coins
    for k in range(4):
        yield np.roll(box, -k, axis=0)


def identify(gray_small_f, box):
    best = (-1, None, None)
    side_len = [np.linalg.norm(box[i] - box[(i + 1) % 4]) for i in range(4)]
    for hyp in hypotheses(box):
        wtop = np.linalg.norm(hyp[1] - hyp[0]); hleft = np.linalg.norm(hyp[3] - hyp[0])
        if hleft <= 0:
            continue
        ratio = wtop / hleft
        if not (1.25 < ratio < 1.95):
            continue
        M = cv2.getPerspectiveTransform(hyp, CANON_SMALL)
        warped = cv2.warpPerspective(gray_small_f, M, (SW, SHh), flags=cv2.INTER_LINEAR, borderValue=-1)
        valid = warped >= 0
        frac = valid.mean()
        for n, ref in refs.items():
            sc = ncc(warped, ref, valid, min_valid=0.12)
            if frac < 0.35:
                sc -= 0.08          # carte très coupée : exiger une meilleure ressemblance
            if sc > best[0]:
                best = (sc, n, hyp)
    return best


def check(gray_small_f, quad_full, side):
    """Ressemblance actuelle d'une piste conservée avec sa référence."""
    q = (quad_full * SCALE).astype(np.float32)
    M = cv2.getPerspectiveTransform(q, CANON_SMALL)
    warped = cv2.warpPerspective(gray_small_f, M, (SW, SHh), flags=cv2.INTER_LINEAR, borderValue=-1)
    return ncc(warped, refs[side], warped >= 0, min_valid=0.12)


def iou(p, q):
    a = cv2.boundingRect(p.astype(np.int32)); b = cv2.boundingRect(q.astype(np.int32))
    x1, y1 = max(a[0], b[0]), max(a[1], b[1]); x2, y2 = min(a[0] + a[2], b[0] + b[2]), min(a[1] + a[3], b[1] + b[3])
    inter = max(0, x2 - x1) * max(0, y2 - y1)
    return inter / float(a[2] * a[3] + b[2] * b[3] - inter + 1e-6)


cap = cv2.VideoCapture(SRC)
fps = cap.get(cv2.CAP_PROP_FPS); W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)); H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{W}x{H}", "-r", str(fps),
                        "-i", "-", "-i", SRC, "-map", "0:v", "-map", "1:a?", "-c:v", "libx264", "-crf", "20", "-preset", "medium",
                        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-shortest", OUT], stdin=subprocess.PIPE)
blurs = []
tracks = []   # dict(poly_canon_quad(full-res), side, last)
log = []
fi = 0
while True:
    ok, frame = cap.read()
    if not ok:
        break
    small = cv2.resize(frame, None, fx=SCALE, fy=SCALE, interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    gf = prep(gray)
    # effacer les traits colorés de l'interface (cadre rouge/vert) avant la recherche de contours
    hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)
    ui = ((hsv[..., 1] > 110) & (hsv[..., 2] > 90) & (((hsv[..., 0] < 12) | (hsv[..., 0] > 168)) | ((hsv[..., 0] > 40) & (hsv[..., 0] < 85))))
    ui = cv2.dilate(ui.astype(np.uint8) * 255, np.ones((5, 5), np.uint8)) > 0
    gray_c = gray.copy()
    if ui.any():
        gray_c[ui] = cv2.medianBlur(gray, 21)[ui]
    dets = []
    unknown = []
    recent = [t for t in tracks if fi - t["last"] <= 30]
    for box in candidates(gray_c):
        sc, side, hyp = identify(gf, box)
        full = box / SCALE
        near = any(iou(t["quad"], full) > 0.25 for t in recent)
        if sc >= ACCEPT or (near and sc >= 0.25):
            dets.append((sc, side, hyp / SCALE))
        else:
            w_ = np.linalg.norm(box[1] - box[0]); h_ = np.linalg.norm(box[3] - box[0])
            r = max(w_, h_) / max(1e-6, min(w_, h_))
            if 1.3 < r < 1.95 and w_ * h_ >= 1500:
                m = np.zeros_like(gray); cv2.fillConvexPoly(m, box.astype(np.int32), 255)
                if cv2.mean(gray, mask=m)[0] >= 110:
                    unknown.append(full)
    dets.sort(key=lambda d: -d[0])
    kept = []
    for d in dets:
        if all(iou(d[2], k[2]) < 0.5 for k in kept):
            kept.append(d)
    # mise à jour des pistes
    seen = set()
    for d in kept:
        match = None
        for t in tracks:
            if iou(t["quad"], d[2]) > 0.3 and id(t) not in seen:
                match = t; break
        if match:
            match.update(quad=d[2], side=d[1], last=fi, score=d[0])
        else:
            match = dict(quad=d[2], side=d[1], last=fi, score=d[0]); tracks.append(match)
        seen.add(id(match))
    alive = []
    for t in tracks:
        if id(t) in seen:
            alive.append(t); continue
        if fi - t["last"] > 120:
            continue
        sc_now = check(gf, t["quad"], t["side"])
        if sc_now >= 0.2 or (fi - t["last"] <= 3 and sc_now >= 0.05):
            alive.append(t)
    tracks = alive
    # cartes non identifiées (flou de bouge) : flouter toute la carte
    for q in unknown:
        if any(iou(q, d[2]) > 0.3 for d in kept):
            continue
        if all(iou(q, u["quad"]) < 0.3 for u in blurs):
            blurs.append(dict(quad=q, last=fi))
        else:
            for u in blurs:
                if iou(q, u["quad"]) >= 0.3:
                    u.update(quad=q, last=fi)
    blurs = [u for u in blurs if fi - u["last"] <= 6]
    for u in blurs:
        q = u["quad"].astype(np.int32)
        x, y, bw, bh = cv2.boundingRect(q)
        x0, y0 = max(0, x - 12), max(0, y - 12); x1, y1 = min(W, x + bw + 12), min(H, y + bh + 12)
        if x1 - x0 < 4 or y1 - y0 < 4:
            continue
        roi = frame[y0:y1, x0:x1]
        bl = cv2.GaussianBlur(roi, (0, 0), 18)
        m = np.zeros(roi.shape[:2], np.uint8)
        cv2.fillConvexPoly(m, cv2.convexHull(q - [x0, y0]), 255)
        m = cv2.dilate(m, np.ones((25, 25), np.uint8))
        roi[m > 0] = bl[m > 0]
    for t in tracks:
        Hm = cv2.getPerspectiveTransform(CANON, t["quad"].astype(np.float32))
        for (a, b, c, d_) in REGIONS[t["side"]]:
            pad = 6
            pts = np.float32([[a - pad, b - pad], [c + pad, b - pad], [c + pad, d_ + pad], [a - pad, d_ + pad]]).reshape(-1, 1, 2)
            poly = cv2.perspectiveTransform(pts, Hm).reshape(-1, 2).astype(np.int32)
            cv2.fillConvexPoly(frame, poly, (255, 255, 255), lineType=cv2.LINE_AA)
    log.append(dict(f=fi, det=[(round(d[0], 2), d[1]) for d in kept], tracks=len(tracks), blur=len(blurs)))
    enc.stdin.write(frame.tobytes())
    fi += 1
    if fi % 300 == 0:
        print(fi, flush=True)
enc.stdin.close(); enc.wait()
json.dump(log, open(LOG, "w"))
print("done", fi)
