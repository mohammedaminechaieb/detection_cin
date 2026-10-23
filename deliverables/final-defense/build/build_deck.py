# -*- coding: utf-8 -*-
"""Génère Soutenance_Stage_ENSI_Final.pptx (14 diapositives + 4 de secours).

Usage : python3 build_deck.py            (depuis n'importe quel dossier)
Dépendances : python-pptx >= 1.0, lxml.
Toutes les valeurs affichées viennent de Rapport_CIN.pdf (voir Audit_Synthese.md).
"""
import copy
import os

from lxml import etree
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Inches, Pt

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "Soutenance_Stage_ENSI_Final.pptx")

# --- Système visuel « plan technique » (audit, section K) -------------------
NAVY = RGBColor(0x1F, 0x3A, 0x5F)    # titres, texte fort, ce qui est retenu
BLUE = RGBColor(0x2E, 0x75, 0xB6)    # ce qui est développé / focus
ORANGE = RGBColor(0xB8, 0x4A, 0x12)  # réserve, limite, non prouvé - uniquement
INK = RGBColor(0x1B, 0x25, 0x30)
MUTED = RGBColor(0x5B, 0x6B, 0x7A)
PANEL = RGBColor(0xEE, 0xF2, 0xF6)
RULE = RGBColor(0xCB, 0xD3, 0xDB)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
FONT = "Arial"
MONO = "Courier New"

SW, SH = 13.333, 7.5
ML = 0.6                      # marge gauche/droite
CW = SW - 2 * ML              # largeur utile
SECTIONS = ["Contexte", "Conception", "Résultats", "Bilan"]
N_MAIN = 17

prs = Presentation()
prs.slide_width, prs.slide_height = Inches(SW), Inches(SH)
BLANK = prs.slide_layouts[6]


def set_theme_fonts():
    """Arial dans le thème : tout texte ajouté plus tard hérite de la même famille."""
    master = prs.slide_masters[0]
    for rel in master.part.rels.values():
        if rel.reltype.endswith("/theme"):
            theme = etree.fromstring(rel.target_part.blob)
            for tag in ("a:majorFont", "a:minorFont"):
                latin = theme.find(".//" + tag + "/a:latin", {"a": "http://schemas.openxmlformats.org/drawingml/2006/main"})
                latin.set("typeface", FONT)
            rel.target_part._blob = etree.tostring(theme, xml_declaration=True, encoding="UTF-8", standalone=True)


set_theme_fonts()


# --- Primitives -------------------------------------------------------------
def I(v):
    return Inches(v)


def text(slide, x, y, w, h, paras, size=20, color=INK, bold=False, align=PP_ALIGN.LEFT,
         anchor=MSO_ANCHOR.TOP, font=FONT, spacing=None, name=None):
    """paras : str | liste de paragraphes ; un paragraphe = str | liste de runs ;
    un run = str | dict(t=, size=, color=, bold=, font=, italic=)."""
    tb = slide.shapes.add_textbox(I(x), I(y), I(w), I(h))
    if name:
        tb.name = name
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    if isinstance(paras, str):
        paras = [paras]
    for i, para in enumerate(paras):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        if spacing:
            p.space_after = Pt(spacing)
        runs = para if isinstance(para, list) else [para]
        for r in runs:
            if isinstance(r, str):
                r = {"t": r}
            run = p.add_run()
            run.text = r["t"].replace("« ", "«\u00a0").replace(" »", "\u00a0»")
            f = run.font
            f.name = r.get("font", font)
            f.size = Pt(r.get("size", size))
            f.bold = r.get("bold", bold)
            f.italic = r.get("italic", False)
            f.color.rgb = r.get("color", color)
    return tb


def _strip_style(shape):
    st = shape._element.find(qn("p:style"))
    if st is not None:
        shape._element.remove(st)


def box(slide, x, y, w, h, fill=None, line=None, lw=1.0, dash=False, shape=MSO_SHAPE.RECTANGLE, name=None):
    s = slide.shapes.add_shape(shape, I(x), I(y), I(w), I(h))
    if name:
        s.name = name
    if fill is None:
        s.fill.background()
    else:
        s.fill.solid()
        s.fill.fore_color.rgb = fill
    if line is None:
        s.line.fill.background()
    else:
        s.line.color.rgb = line
        s.line.width = Pt(lw)
        if dash:
            s.line.dash_style = 4  # MSO_LINE.DASH
    _strip_style(s)
    if s.has_text_frame:
        s.text_frame.text = ""
    return s


def line(slide, x1, y1, x2, y2, color=RULE, lw=1.0, arrow=False, dash=False):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, I(x1), I(y1), I(x2), I(y2))
    _strip_style(c)
    c.line.color.rgb = color
    c.line.width = Pt(lw)
    if dash:
        c.line.dash_style = 4
    if arrow:
        ln = c.line._get_or_add_ln()
        tail = etree.SubElement(ln, qn("a:tailEnd"))
        tail.set("type", "triangle")
        tail.set("w", "med")
        tail.set("h", "med")
    return c


def picture(slide, path, x, y, w=None, h=None, alt="", frame=True):
    kw = {}
    if w is not None:
        kw["width"] = I(w)
    if h is not None:
        kw["height"] = I(h)
    pic = slide.shapes.add_picture(path, I(x), I(y), **kw)
    pic._element.nvPicPr.cNvPr.set("descr", alt)
    if frame:
        pic.line.color.rgb = RULE
        pic.line.width = Pt(0.75)
    return pic


def notes(slide, body):
    slide.notes_slide.notes_text_frame.text = body.strip()


def chrome(slide, n, section=None, backup=None):
    """Repère de section (haut droite), pied de page et numéro."""
    _c = mark(slide)
    if backup:
        pill = box(slide, SW - ML - 1.45, 0.42, 1.45, 0.34, fill=PANEL)
        text(slide, SW - ML - 1.45, 0.42, 1.45, 0.34, "Secours " + backup, size=12, bold=True,
             color=MUTED, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    elif section:
        runs = []
        for i, s in enumerate(SECTIONS):
            if i:
                runs.append({"t": "   ·   ", "color": RULE})
            runs.append({"t": s.upper(), "bold": s == section, "color": BLUE if s == section else MUTED})
        text(slide, SW - ML - 6.2, 0.47, 6.2, 0.3, [runs], size=11, align=PP_ALIGN.RIGHT)
    line(slide, ML, 6.98, SW - ML, 6.98, color=RULE, lw=0.75)
    text(slide, ML, 7.06, 8, 0.25, "Avatar-ID · autocapture de la CIN · Mohammed Amine Chaieb · ENSI 2025/2026",
         size=11, color=MUTED)
    label = f"{n} / {N_MAIN}" if not backup else f"Secours {backup}"
    text(slide, SW - ML - 2, 7.06, 2, 0.25, label, size=11, color=MUTED, align=PP_ALIGN.RIGHT)
    CHROME[slide.slide_id] = set(since(slide, _c))


def title(slide, t, y=0.85, size=28, w=CW):
    return text(slide, ML, y, w, 1.1, t, size=size, bold=True, color=NAVY, name="Titre")


ANIM = {}       # slide -> liste de groupes (un groupe = un clic)
ANIM_NOTE = {}  # slide -> consigne de clics ajoutée aux notes
AUTO_BUILD = False  # True : construction automatique bande par bande (désactivée : tout passe par des clics)
UNITS = {}      # slide -> ensembles de formes à faire apparaître d'un bloc
AUTOPLAY = []   # (slide, vidéo) lancées automatiquement
CHROME = {}     # slide -> formes fixes (repère, pied de page), jamais animées


def mark(slide):
    return {sh.shape_id for sh in slide.shapes}


def since(slide, before):
    return [sh.shape_id for sh in slide.shapes if sh.shape_id not in before]


def unit(slide, ids):
    """Formes qui apparaissent ensemble dans la construction automatique."""
    UNITS.setdefault(slide.slide_id, []).append(set(ids))


def step(slide, ids):
    ANIM.setdefault(slide.slide_id, []).append(list(ids))


def _apply_animations():
    """Transition fondu sur toutes les diapositives ; apparitions en fondu, au clic,
    sur les diapositives qui construisent un raisonnement."""
    P = "http://schemas.openxmlformats.org/presentationml/2006/main"
    autoplay = dict(AUTOPLAY)
    for sl in prs.slides:
        root = sl._element
        old = root.find(qn("p:timing"))
        if old is not None:
            root.remove(old)  # minutage par défaut de python-pptx (vidéo au clic), remplacé ci-dessous
        tr = etree.SubElement(root, qn("p:transition"))
        tr.set("spd", "med")
        etree.SubElement(tr, qn("p:fade"))
        if sl.slide_id in autoplay:
            vid = autoplay[sl.slide_id]
            root.append(etree.fromstring(f"""<p:timing xmlns:p="{P}"><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst><p:par><p:cTn id="3" fill="hold"><p:stCondLst><p:cond delay="indefinite"/><p:cond evt="onBegin" delay="0"><p:tn val="2"/></p:cond></p:stCondLst><p:childTnLst><p:par><p:cTn id="4" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst><p:par><p:cTn id="5" presetID="1" presetClass="mediacall" presetSubtype="0" fill="hold" nodeType="afterEffect"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst><p:cmd type="call" cmd="playFrom(0.0)"><p:cBhvr><p:cTn id="6" dur="39733" fill="hold"/><p:tgtEl><p:spTgt spid="{vid}"/></p:tgtEl></p:cBhvr></p:cmd></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn><p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst><p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq><p:video><p:cMediaNode vol="80000" mute="1"><p:cTn id="7" fill="hold" display="0"><p:stCondLst><p:cond delay="indefinite"/></p:stCondLst></p:cTn><p:tgtEl><p:spTgt spid="{vid}"/></p:tgtEl></p:cMediaNode></p:video></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"""))
            continue
        groups = ANIM.get(sl.slide_id, [])
        clicked = {i for g in groups for i in g}
        fixed = CHROME.get(sl.slide_id, set())
        # Apparition automatique, bande par bande (de haut en bas) ; le titre d'abord.
        content = [sh for sh in sl.shapes if sh.shape_id not in clicked and sh.shape_id not in fixed]
        title_ids = [sh.shape_id for sh in content if sh.name == "Titre"]
        rest = [sh for sh in content if sh.name != "Titre"]
        # une forme contenue dans un cadre (rectangle sans texte) apparaît avec lui
        frames = [sh for sh in rest if sh.shape_type == 1 and not sh.text_frame.text.strip()
                  and sh.width > Inches(0.6) and sh.height > Inches(0.4)]

        def key(sh):
            best = None
            for f in frames:
                if f is not sh and f.left <= sh.left < f.left + f.width and f.top <= sh.top < f.top + f.height \
                        and (best is None or f.width * f.height > best.width * best.height):
                    best = f
            return best.top if best is not None else sh.top
        units = UNITS.get(sl.slide_id, [])
        groups_of = {}
        for sh in rest:
            u = next((i for i, us in enumerate(units) if sh.shape_id in us), None)
            groups_of.setdefault(("u", u) if u is not None else ("s", sh.shape_id), []).append(sh)
        blocks = sorted(groups_of.values(), key=lambda b: min(key(sh) for sh in b))
        bands, last_top = [], None
        for blk in blocks:
            k_ = min(key(sh) for sh in blk)
            if last_top is None or k_ - last_top > Inches(0.3):
                bands.append([])
            bands[-1].append((k_, blk))
            last_top = max(last_top or 0, k_) if len(blk) == 1 else k_
        while len(bands) > 6:
            gaps = [bands[i + 1][0][0] - bands[i][-1][0] for i in range(len(bands) - 1)]
            j = gaps.index(min(gaps))
            bands[j:j + 2] = [bands[j] + bands[j + 1]]
        auto = ([title_ids] if title_ids else []) + [[sh.shape_id for _, blk in bd for sh in blk] for bd in bands]
        if not AUTO_BUILD:
            auto = []
        nid = [2]

        def ctn_id():
            nid[0] += 1
            return str(nid[0])

        def effect(spid, node, dur):
            return (f'<p:par><p:cTn id="{ctn_id()}" presetID="10" presetClass="entr" presetSubtype="0" fill="hold" nodeType="{node}">'
                    f'<p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst><p:set><p:cBhvr><p:cTn id="{ctn_id()}" dur="1" fill="hold">'
                    f'<p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn><p:tgtEl><p:spTgt spid="{spid}"/></p:tgtEl><p:attrNameLst>'
                    f'<p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val="visible"/></p:to></p:set>'
                    f'<p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="{ctn_id()}" dur="{dur}"/><p:tgtEl><p:spTgt spid="{spid}"/>'
                    f'</p:tgtEl></p:cBhvr></p:animEffect></p:childTnLst></p:cTn></p:par>')
        seq = []
        if auto:
            outer = ctn_id()
            inner = []
            for k, g in enumerate(auto):
                pid = ctn_id()
                eff = "".join(effect(spid, "afterEffect" if i == 0 else "withEffect", 350) for i, spid in enumerate(g))
                inner.append(f'<p:par><p:cTn id="{pid}" fill="hold"><p:stCondLst><p:cond delay="{k * 250}"/></p:stCondLst><p:childTnLst>{eff}</p:childTnLst></p:cTn></p:par>')
            seq.append(f'<p:par><p:cTn id="{outer}" fill="hold"><p:stCondLst><p:cond delay="indefinite"/><p:cond evt="onBegin" delay="0"><p:tn val="2"/></p:cond></p:stCondLst><p:childTnLst>{"".join(inner)}</p:childTnLst></p:cTn></p:par>')
        for g in groups:
            a_, b_ = ctn_id(), ctn_id()
            eff = "".join(effect(spid, "clickEffect" if i == 0 else "withEffect", 400) for i, spid in enumerate(g))
            seq.append(f'<p:par><p:cTn id="{a_}" fill="hold"><p:stCondLst><p:cond delay="indefinite"/></p:stCondLst><p:childTnLst><p:par><p:cTn id="{b_}" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>{eff}</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>')
        if not seq:
            continue
        all_ids = [i for g in auto + groups for i in g]
        bld = "".join(f'<p:bldP spid="{spid}" grpId="0"/>' for spid in all_ids
                      if sl.shapes._spTree.xpath(f'./*[*/p:cNvPr/@id="{spid}"]')[0].tag == qn("p:sp"))
        xml = f"""<p:timing xmlns:p="{P}"><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst><p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>{''.join(seq)}</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst><p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq></p:childTnLst></p:cTn></p:par></p:tnLst>{'<p:bldLst>' + bld + '</p:bldLst>' if bld else ''}</p:timing>"""
        root.append(etree.fromstring(xml))
        if sl.slide_id in ANIM_NOTE:
            tf = sl.notes_slide.notes_text_frame
            lines = tf.text.split("\n")
            tf.text = "\n".join(lines[:1] + ["", ANIM_NOTE[sl.slide_id]] + lines[1:])


def new_slide():
    return prs.slides.add_slide(BLANK)


def card_outline(slide, x, y, w, color=NAVY, lw=1.25, corners=True):
    """Contour d'une carte ID-1 (85,6 x 54 mm) et ses quatre coins détectés."""
    h = w * 54.0 / 85.6
    c = box(slide, x, y, w, h, line=color, lw=lw, shape=MSO_SHAPE.ROUNDED_RECTANGLE)
    c.adjustments[0] = 0.06
    if corners:
        t = w * 0.07
        for (cx, cy, dx, dy) in [(x, y, 1, 1), (x + w, y, -1, 1), (x + w, y + h, -1, -1), (x, y + h, 1, -1)]:
            line(slide, cx - dx * 0.06, cy - dy * 0.06, cx + dx * t, cy - dy * 0.06, color=BLUE, lw=2.5)
            line(slide, cx - dx * 0.06, cy - dy * 0.06, cx - dx * 0.06, cy + dy * t, color=BLUE, lw=2.5)
    return h


A = lambda name: os.path.join(ASSETS, name)  # noqa: E731

# ===========================================================================
# 1 - Titre
# ===========================================================================
s = new_slide()
x0 = ML
for name, hh in (("logo_manouba.png", 0.78), ("logo_ensi.png", 0.78), ("logo_codingaholic.png", 0.62)):
    p = picture(s, A(name), x0, 0.55 + (0.78 - hh), h=hh, alt=name.replace("logo_", "Logo ").replace(".png", ""), frame=False)
    x0 += p.width / 914400 + 0.35
text(s, ML, 1.95, 7.6, 0.35, "SOUTENANCE DE STAGE D'ÉTÉ · 2025/2026", size=14, bold=True, color=BLUE)
text(s, ML, 2.35, 7.6, 1.8, "Détection automatique et autocapture de la CIN tunisienne", size=36, bold=True,
     color=NAVY, name="Titre")
text(s, ML, 4.25, 7.2, 0.8, "Module de capture recto/verso pour Avatar-ID, application Flutter de vérification d'identité à distance",
     size=20, color=INK)
text(s, ML, 5.3, 7.75, 1.3, [
    [{"t": "Mohammed Amine Chaieb", "bold": True, "size": 20, "color": NAVY}],
    "Codingaholic, La Marsa · encadrant : M. Jendoubi Mohamed Khalil",
    "Université de la Manouba · École Nationale des Sciences de l'Informatique",
], size=16, color=MUTED, spacing=4)
ch = card_outline(s, 8.55, 2.05, 4.15)
text(s, 8.55, 2.05 + ch + 0.22, 4.15, 0.6, [
    [{"t": "Format ID-1 · 85,6 × 54 mm · ", "color": MUTED}, {"t": "r₀ = 1,586", "bold": True, "color": NAVY}],
    [{"t": "les quatre coins que le module doit trouver, seul, dans le flux caméra", "color": MUTED}],
], size=14, align=PP_ALIGN.CENTER)
notes(s, """
⏱ 0:20 (cumul 0:20)

TEXTE ORAL
Bonjour. Je présente mon stage d'été de six semaines chez Codingaholic, encadré par M. Jendoubi : un module mobile qui détecte et capture automatiquement le recto puis le verso de la carte d'identité tunisienne, pour l'application Avatar-ID.

TRANSITION — « D'abord, le contexte. »

QUESTION PROBABLE
– « Quel était votre périmètre exact ? » → la capture : détection, contrôle de qualité, recto/verso, recadrage, amélioration. La vivacité, la comparaison des photos, l'OCR et l'enregistrement sont les étapes suivantes d'Avatar-ID (diapositive 2).
""")

# ===========================================================================
# 2 - Place du module dans Avatar-ID
# ===========================================================================
s = new_slide()
chrome(s, 2, "Contexte")
title(s, "Mon module est la première étape du parcours Avatar-ID : sa qualité conditionne la suite")
stages = [("Capture de la CIN", ["détection", "qualité d'image", "recto puis verso", "recadrage, amélioration"]),
          ("Test de vivacité", ["la personne est présente, en direct"]),
          ("Comparaison des photos", ["photo de la CIN ↔ visage du test de vivacité"]),
          ("OCR", ["lecture des champs de la carte"]),
          ("Enregistrement", ["sauvegarde du résultat"])]
ws3 = [2.9, 2.05, 2.05, 2.05, 2.05]
gap3 = (CW - sum(ws3)) / 4
y3, h3 = 2.55, 2.3
xx = ML
xs3 = []
for i, ((h1, items_), wv) in enumerate(zip(stages, ws3)):
    mine = i == 0
    box(s, xx, y3, wv, h3, fill=WHITE if mine else PANEL, line=BLUE if mine else RULE, lw=2.25 if mine else 1.0)
    text(s, xx + 0.15, y3 + 0.12, wv - 0.3, 0.3, str(i + 1), size=14, bold=True, color=BLUE)
    text(s, xx + 0.15, y3 + 0.42, wv - 0.2, 0.75, h1, size=17 if mine else 16, bold=True, color=NAVY)
    text(s, xx + 0.15, y3 + (0.85 if mine else 1.15), wv - 0.3, 1.3, items_, size=16 if mine else 15, color=INK, spacing=2)
    if i == 0:
        _m = mark(s)
    if i < 4:
        line(s, xx + wv + 0.04, y3 + h3 / 2, xx + wv + gap3 - 0.04, y3 + h3 / 2, color=NAVY, lw=1.5, arrow=True)
    xs3.append(xx)
    xx += wv + gap3
_g = since(s, _m)
# accolades de périmètre
line(s, ML, 2.35, ML + ws3[0], 2.35, color=BLUE, lw=3.0)
text(s, ML, 2.0, ws3[0], 0.3, "CE STAGE", size=13, bold=True, color=BLUE)
_m = mark(s)
line(s, xs3[1], 2.35, SW - ML, 2.35, color=MUTED, lw=1.5)
text(s, xs3[1], 2.0, 6.0, 0.3, "SUITE DU PARCOURS AVATAR-ID", size=13, bold=True, color=MUTED)
step(s, _g + since(s, _m))
_m = mark(s)
wv2 = (CW - 0.6) / 2
text(s, ML, 5.2, wv2, 1.4, [[{"t": "Ce que le module transmet : ", "bold": True, "color": NAVY},
     "le recto et le verso redressés et orientés, ainsi que la page A4 composée."]], size=18, color=INK)
text(s, ML + wv2 + 0.6, 5.2, wv2, 1.4, [[{"t": "Pourquoi la qualité compte : ", "bold": True, "color": NAVY},
     "une carte nette, bien cadrée et à l'endroit alimente directement la comparaison des photos et l'OCR."]], size=18, color=INK)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 2 clics : 1) étapes 2 à 5 d'Avatar-ID, après « Mon module est la première » ; 2) les deux conclusions du bas."
notes(s, """
⏱ 0:30 (cumul 0:50)

TEXTE ORAL
Avatar-ID vérifie l'identité à distance, comme un KYC bancaire. Mon module en est la première étape : la capture de la carte. [clic] Ensuite, Avatar-ID réalise le test de vivacité, compare la photo de la carte au visage, lit la carte par OCR et enregistre le résultat. [clic] La qualité de ma capture conditionne donc toute la suite.

TRANSITION — « Or cette capture échoue souvent. »

QUESTIONS PROBABLES (préparation, ne pas lire)
– « Avez-vous développé la vivacité ou l'OCR ? » → non, ce sont les étapes suivantes d'Avatar-ID ; mon périmètre est la capture.
– « Sous quelle forme passez-vous les images ? » → deux images (Uint8List) et, le cas échéant, la page d'impression (rapport §8.2.5).
""")

# ===========================================================================
# 3 - Problème
# ===========================================================================
s = new_slide()
chrome(s, 3, "Contexte")
title(s, "Une photo libre de CIN peut être floue, de travers ou envoyée deux fois")
labels = [("Floue", "image inexploitable"), ("De travers", "carte mal cadrée"), ("Deux fois le recto", "verso jamais fourni")]
cx = ML
for i, (lab, sub) in enumerate(labels):
    _m = mark(s)
    bx = cx + i * 4.11
    box(s, bx, 2.05, 3.85, 2.25, fill=PANEL)
    if i == 0:
        for k, off in enumerate((0.16, 0.08, 0.0)):
            card_outline(s, bx + 0.95 + off, 2.45 + off * 0.6, 1.95, color=NAVY if k == 2 else RULE, lw=1.0, corners=False)
    elif i == 1:
        c = box(s, bx + 1.0, 2.5, 1.95, 1.23, line=NAVY, lw=1.25, shape=MSO_SHAPE.ROUNDED_RECTANGLE)
        c.adjustments[0] = 0.06
        c.rotation = -14
    else:
        for k, off in enumerate((0.0, 0.42)):
            c = box(s, bx + 0.75 + off, 2.42 + off * 0.5, 1.85, 1.17, fill=WHITE, line=NAVY, lw=1.25, shape=MSO_SHAPE.ROUNDED_RECTANGLE)
            c.adjustments[0] = 0.06
            text(s, bx + 0.75 + off, 2.42 + off * 0.5 + 0.35, 1.85, 0.4, "recto", size=16, color=NAVY, align=PP_ALIGN.CENTER)
    text(s, bx, 4.42, 3.85, 0.65, [[{"t": lab, "bold": True, "color": NAVY, "size": 20}], sub], size=16, color=MUTED,
         align=PP_ALIGN.CENTER)
    step(s, since(s, _m))
_m = mark(s)
text(s, ML, 5.3, 8.3, 1.2, [
    [{"t": "Problématique — ", "bold": True, "color": NAVY},
     {"t": "comment détecter de façon fiable et en temps réel les contours d'une CIN dans un flux caméra mobile, quels que soient l'éclairage et l'arrière-plan ?"}],
], size=20)
text(s, 9.3, 5.3, SW - ML - 9.3, 1.3, [
    [{"t": "Sans guidage : ", "bold": True, "color": NAVY}, "contrôle humain coûteux, nouvelle saisie, et étapes suivantes (photos, OCR) dégradées."],
], size=16, color=MUTED, spacing=6)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 4 clics : les trois défauts un par un (flou, de travers, deux fois le recto), puis la problématique."
notes(s, """
⏱ 0:30 (cumul 1:20)

TEXTE ORAL
Une simple photo de la carte est souvent [clic] floue, [clic] de travers, [clic] ou c'est deux fois le recto au lieu du verso. [clic] D'où ma problématique : détecter en temps réel et de façon fiable les contours de la CIN, quels que soient l'éclairage et l'arrière-plan.

TRANSITION — « Voici ce que le module devait faire. »

QUESTION PROBABLE
– « Pourquoi ne pas utiliser une plateforme KYC existante (Onfido, Jumio…) ? » → données d'identité envoyées à un tiers, coût de licence, dépendance réseau au moment de la capture, peu de personnalisation pour la CIN tunisienne (rapport, tableau 1.1). Avatar-ID a choisi un module interne, sur l'appareil.
""")

# ===========================================================================
# 3 - Objectifs et cibles
# ===========================================================================
s = new_slide()
chrome(s, 4, "Contexte")
title(s, "Cinq fonctions à automatiser, trois cibles chiffrées, deux plateformes")
text(s, ML, 2.0, 5.6, 0.35, "CE QUE LE MODULE DOIT FAIRE", size=13, bold=True, color=BLUE)
_m = mark(s)
funcs = ["Détecter la carte et ses contours", "Contrôler netteté, luminosité, stabilité", "Distinguer recto et verso, dans l'ordre",
         "Capturer seul, sans bouton", "Recadrer et améliorer l'image"]
for i, f in enumerate(funcs):
    yy = 2.5 + i * 0.72
    text(s, ML, yy, 0.5, 0.5, f"{i + 1}", size=24, bold=True, color=BLUE)
    text(s, ML + 0.55, yy + 0.04, 5.2, 0.5, f, size=20)
    if i < 4:
        line(s, ML, yy + 0.62, ML + 5.6, yy + 0.62, color=RULE, lw=0.5)
step(s, since(s, _m))
xr = 7.15
text(s, xr, 2.0, 5.6, 0.35, "CIBLES DU CAHIER DES CHARGES", size=13, bold=True, color=BLUE)
_m = mark(s)
targets = [("< 100 ms", "de traitement par image, idéalement"),
           ("≥ 90 %", "de recto/verso bien reconnus, en conditions normales"),
           ("≈ 2 s", "entre carte bien positionnée et capture")]
for i, (v, d) in enumerate(targets):
    yy = 2.5 + i * 1.08
    text(s, xr, yy, 2.25, 0.8, v, size=36, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
    text(s, xr + 2.35, yy, 3.25, 0.8, d, size=16, color=INK, anchor=MSO_ANCHOR.MIDDLE)
step(s, since(s, _m))
_m = mark(s)
box(s, xr, 5.85, SW - ML - xr, 0.62, fill=PANEL)
text(s, xr + 0.2, 5.85, SW - ML - xr - 0.4, 0.62, [[{"t": "Android et iOS", "bold": True, "color": NAVY},
     " · un seul code pour les deux"]], size=16, anchor=MSO_ANCHOR.MIDDLE)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 3 clics : 1) les cinq fonctions ; 2) les trois cibles ; 3) Android et iOS."
notes(s, """
⏱ 0:35 (cumul 1:55)

TEXTE ORAL
[clic] Cinq fonctions : détecter la carte, contrôler la netteté, la luminosité et la stabilité, distinguer le recto du verso, capturer sans bouton, puis recadrer et améliorer. [clic] Trois cibles : moins de 100 millisecondes par image, au moins 90 % de recto/verso reconnus en conditions normales, et environ deux secondes jusqu'à la capture. [clic] Le tout sur Android et iOS, avec un seul code, en six semaines.

TRANSITION — « Cette double plateforme a dicté la technologie. »

QUESTION PROBABLE
– « Les besoins secondaires ? » → reprise manuelle après capture (implémentée), anti-doublon (implémenté), alerte si aucune carte n'est détectée après un délai (prévue en perspective).
""")

# ===========================================================================
# 4 - Choix technologique
# ===========================================================================
s = new_slide()
chrome(s, 5, "Contexte")
title(s, "Seul OpenCV tenait Android + iOS en six semaines, sans jeu de données annoté")
rows = [["Critère", "ML Kit\nDocument Scanner", "Modèle entraîné\nsur mesure", "OpenCV\n(retenu)"],
        ["Support iOS", "Non", "Oui, si entraîné", "Oui"],
        ["Jeu de données", "Aucun", "Plusieurs centaines\nd'images annotées", "Aucun"],
        ["Tenable en 6 semaines", "Oui", "Non", "Oui"],
        ["Effort de réglage", "Faible", "Élevé (entraînement)", "Moyen (seuils empiriques)"]]
blockers = {(1, 1), (3, 2), (2, 2)}
tbl = s.shapes.add_table(5, 4, I(ML), I(2.0), I(CW), I(3.18)).table
widths = [3.0, 3.0, 3.0, CW - 9.0]
for j, wv in enumerate(widths):
    tbl.columns[j].width = I(wv)
for i, r in enumerate(rows):
    tbl.rows[i].height = I(0.78 if i == 0 else 0.6)
    for j, v in enumerate(r):
        cell = tbl.cell(i, j)
        cell.margin_left = cell.margin_right = I(0.14)
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
        cell.fill.solid()
        cell.fill.fore_color.rgb = NAVY if (j == 3 and i == 0) else (PANEL if j == 3 or i == 0 else WHITE)
        tf = cell.text_frame
        tf.text = ""
        for k, part in enumerate(v.split("\n")):
            p = tf.paragraphs[0] if k == 0 else tf.add_paragraph()
            run = p.add_run()
            run.text = part
            run.font.name = FONT
            run.font.size = Pt(18 if i else 17)
            run.font.bold = i == 0 or j == 0 or j == 3 or (i, j) in blockers
            run.font.color.rgb = WHITE if (j == 3 and i == 0) else (ORANGE if (i, j) in blockers else (NAVY if j in (0, 3) or i == 0 else INK))
tblpr = s.shapes[-1]._element.graphic.graphicData.tbl.tblPr
tblpr.set("firstRow", "0")
tblpr.set("bandRow", "0")
for st in tblpr.findall(qn("a:tableStyleId")):
    tblpr.remove(st)
_m = mark(s)
text(s, ML, 5.62, 2.0, 0.5, "PILE RETENUE", size=13, bold=True, color=BLUE, anchor=MSO_ANCHOR.MIDDLE)
xl = ML + 2.0
for img, lab in (("logo_tech_flutter.png", "Flutter"), ("logo_tech_dart.png", "Dart"), ("logo_tech_opencv.png", "OpenCV · opencv_dart")):
    pl = picture(s, A(img), xl, 5.6, h=0.55, alt="Logo " + lab.split(" ")[0], frame=False)
    wl = pl.width / 914400
    text(s, xl + wl + 0.15, 5.6, 3.2, 0.55, lab, size=18, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
    xl += wl + 0.15 + (1.5 if lab != "Dart" else 1.1)
step(s, since(s, _m))
_m = mark(s)
text(s, ML, 6.38, CW, 0.5, [
    [{"t": "En orange : le critère qui élimine l'option. ", "color": ORANGE, "bold": True},
     "Vision/VisionKit (iOS) écarté aussi : deux chaînes de détection à maintenir."],
], size=16, color=MUTED)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 2 clics : 1) la pile retenue (logos) ; 2) la remarque en orange."
notes(s, """
⏱ 0:35 (cumul 2:30)

TEXTE ORAL
Le Document Scanner de ML Kit n'existe que sur Android. Un modèle entraîné sur mesure exigeait plusieurs centaines d'images de CIN annotées, impossible à constituer en six semaines. J'ai donc retenu OpenCV : multiplateforme et sans entraînement, au prix d'un réglage empirique des seuils. [clic] La pile : Flutter et Dart pour l'application, OpenCV via le binding opencv_dart. [clic] En orange, le critère qui élimine chaque option.

TRANSITION — « Voyons l'organisation du code. »

QUESTIONS PROBABLES
– « Pourquoi pas du deep learning ? » → pas de jeu de données annoté possible, pas de jeu public pour des raisons de confidentialité, et six semaines pour toute la fonctionnalité (rapport p. 15).
– « Utilisez-vous un modèle appris quelque part ? » → oui, un seul : la cascade de Haar de détection de visage, pré-entraînée et fournie par OpenCV. Je ne l'ai pas entraînée.
""")

# ===========================================================================
# 5 - Architecture
# ===========================================================================
s = new_slide()
chrome(s, 6, "Conception")
title(s, "Un domaine sans Flutter ni OpenCV rend la logique testable sans caméra")
text(s, ML, 2.0, 5.6, 0.35, "UN MODULE TYPE (CLEAN ARCHITECTURE)", size=13, bold=True, color=BLUE)
layers = [("presentation", "écrans, view-models (ChangeNotifier)", RULE, None),
          ("domain", "entités et cas d'usage · Dart pur", BLUE, PANEL),
          ("data", "détecteurs OpenCV, services, dépôts", RULE, None)]
ys = [2.5, 3.85, 5.2]
for (nm, d, lc, fl), yy in zip(layers, ys):
    b = box(s, ML, yy, 4.2, 0.95, fill=fl, line=lc, lw=2.0 if nm == "domain" else 1.0)
    text(s, ML + 0.2, yy + 0.1, 3.9, 0.4, nm, size=18, bold=True, color=NAVY, font=MONO)
    text(s, ML + 0.2, yy + 0.5, 3.9, 0.4, d, size=16, color=INK)
line(s, ML + 2.1, 3.45, ML + 2.1, 3.85, color=NAVY, lw=1.5, arrow=True)
text(s, ML + 2.25, 3.47, 2.0, 0.35, "dépend de", size=14, color=MUTED)
line(s, ML + 2.1, 5.2, ML + 2.1, 4.8, color=NAVY, lw=1.5, arrow=True)
text(s, ML + 2.25, 4.84, 2.0, 0.35, "implémente", size=14, color=MUTED)
# matrice modules x couches (annexe A du rapport)
_m = mark(s)
xm = 5.75
text(s, xm, 2.0, 7.0, 0.35, "SEPT MODULES FEATURE-FIRST : COUCHES RÉELLEMENT PRÉSENTES", size=13, bold=True, color=BLUE)
mods = [("camera_capture", "P"), ("document_detection", "PDA"), ("image_quality", "A"), ("autocapture", "PD"),
        ("image_postprocessing", "PDA"), ("result_preview", "PD"), ("capture_history", "P")]
cols = [("P", "présentation"), ("D", "domaine"), ("A", "données")]
xc = [xm + 3.75, xm + 5.0, xm + 6.15]
for (k, lab), xx in zip(cols, xc):
    text(s, xx - 0.62, 2.45, 1.24, 0.3, lab, size=14, color=MUTED, align=PP_ALIGN.CENTER)
for i, (m, has) in enumerate(mods):
    yy = 2.85 + i * 0.47
    text(s, xm, yy, 3.6, 0.4, m, size=16, color=INK, font=MONO, anchor=MSO_ANCHOR.MIDDLE)
    for (k, _), xx in zip(cols, xc):
        if k in has:
            d = box(s, xx - 0.11, yy + 0.09, 0.22, 0.22, fill=BLUE if k == "D" else NAVY, shape=MSO_SHAPE.OVAL)
        else:
            line(s, xx - 0.1, yy + 0.2, xx + 0.1, yy + 0.2, color=RULE, lw=1.0)
    line(s, xm, yy + 0.44, xm + 6.75, yy + 0.44, color=RULE, lw=0.5)
text(s, xm, 6.2, 7.0, 0.6, [[{"t": "+ transverses : ", "bold": True, "color": NAVY},
     {"t": "core/services", "font": MONO}, " (caméra, cascade, stockage) et ", {"t": "shared/utils", "font": MONO},
     " (conversion d'image, stabilisation)"]], size=14, color=MUTED)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 1 clic : la matrice des sept modules, après avoir expliqué le module type."
notes(s, """
⏱ 0:30 (cumul 3:00)

TEXTE ORAL
Le code suit la Clean Architecture, découpée par fonctionnalité. La couche présentation dépend du domaine, et la couche données l'implémente. La clé est le domaine : il ne dépend ni de Flutter ni d'OpenCV, donc la machine à états ou la géométrie se testent sans caméra ni émulateur. [clic] Chaque module ne prend que les couches dont il a besoin.

TRANSITION — « Passons au cœur : la détection. »

QUESTION PROBABLE
– « Pourquoi feature-first ? » → l'arborescence suit le plan en six étapes, chaque étape livrant un ou deux modules ; et un module ne peut pas casser silencieusement un autre, puisqu'ils ne partagent que des interfaces de domaine explicites (rapport §2.6.1).
""")

# ===========================================================================
# 6 - Pipeline
# ===========================================================================
s = new_slide()
chrome(s, 7, "Conception")
title(s, "Quatre passes de contours et un score géométrique retiennent le quadrilatère de la carte")
steps = [("1", "Conversion", "frame YUV420 ou BGRA → Mat OpenCV", "dev"),
         ("2", "CLAHE", "contraste local\nrenforcé", "cv"),
         ("3", "4 passes → masques", "Canny (seuils ×0,66/×1,33 de la médiane) · seuillage adaptatif · saturation HSV + Otsu · gradient morphologique", "mix"),
         ("4", "Score", "0,8 × proportion\n+ 0,2 × taille\nretenu si ≥ 0,30\n×0,85 si quad approché", "dev"),
         ("5", "Redressement", "homographie\n→ 856 × 540 px\nquad resserré de 1,5 %", "cv")]
wbox = [2.05, 1.65, 3.35, 2.1, 2.05]
gap = (CW - sum(wbox)) / 4
xx = ML
y0, hb = 2.15, 2.35
for (n, h1, d, kind), wv in zip(steps, wbox):
    fill = PANEL if kind == "cv" else WHITE
    lc = RULE if kind == "cv" else BLUE
    box(s, xx, y0, wv, hb, fill=fill, line=lc, lw=2.0 if kind != "cv" else 1.0)
    text(s, xx + 0.15, y0 + 0.12, wv - 0.3, 0.3, n, size=14, bold=True, color=BLUE)
    text(s, xx + 0.15, y0 + 0.42, wv - 0.25, 0.4, h1, size=17, bold=True, color=NAVY)
    text(s, xx + 0.15, y0 + 0.88, wv - 0.3, hb - 0.95, d.split("\n"), size=16, color=INK)
    if xx + wv < SW - ML - 0.1:
        line(s, xx + wv + 0.04, y0 + hb / 2, xx + wv + gap - 0.04, y0 + hb / 2, color=NAVY, lw=1.5, arrow=True)
    xx += wv + gap
# bande sous le flux : ce qui est conçu dans le stage
_m = mark(s)
yb = 4.85
text(s, ML, yb, CW, 0.35, "CONÇU ET DÉVELOPPÉ PENDANT LE STAGE, AUTOUR DES PRIMITIVES OPENCV", size=13, bold=True, color=BLUE)
items = [("Sortie anticipée", "les passes suivantes ne tournent que si aucun candidat n'atteint 0,65"),
         ("Suivi", "carte trouvée : recherche limitée à ±20 % autour du quad précédent"),
         ("Garde-fous", "rejet des quads collés au bord ou couvrant plus de 75 % de l'image"),
         ("Isolate Dart", "pipeline hors du thread d'interface ; frame ignorée si l'isolate est occupé")]
wi = (CW - 3 * 0.3) / 4
for i, (h1, d) in enumerate(items):
    xi = ML + i * (wi + 0.3)
    line(s, xi, yb + 0.47, xi, yb + 1.55, color=BLUE, lw=2.0)
    text(s, xi + 0.15, yb + 0.45, wi - 0.2, 1.2, [[{"t": h1, "bold": True, "color": NAVY}], d], size=16, color=INK)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 1 clic : la bande « conçu et développé pendant le stage », au moment de « Autour d'OpenCV, j'ai conçu »."
box(s, ML, 6.62, 0.3, 0.2, fill=PANEL, line=RULE)
text(s, ML + 0.4, 6.6, 3.2, 0.25, "primitive OpenCV", size=12, color=MUTED)
box(s, ML + 2.2, 6.62, 0.3, 0.2, fill=WHITE, line=BLUE, lw=1.5)
text(s, ML + 2.6, 6.6, 5, 0.25, "conçu dans le stage (la passe 3 combine les deux)", size=12, color=MUTED)
notes(s, """
⏱ 1:00 (cumul 4:00)

TEXTE ORAL
Chaque image caméra, en YUV420 ou BGRA, devient une matrice OpenCV. Un CLAHE, une égalisation d'histogramme locale, renforce le contraste. Quatre passes produisent ensuite des masques de contours : Canny, avec des seuils à 0,66 et 1,33 fois la médiane ; un seuillage adaptatif ; la saturation HSV avec Otsu ; et, en dernier recours, un gradient morphologique. Chaque contour est simplifié en polygone ; un score de 80 % sur la proportion du format ID-1 et 20 % sur la taille retient le meilleur quadrilatère au-dessus de 0,30. Une homographie le redresse en 856 par 540 pixels. [clic] Autour de ces primitives, j'ai conçu la sortie anticipée à 0,65, le suivi à plus ou moins 20 % autour de la position précédente, les garde-fous contre un faux quadrilatère, et un isolate Dart qui garde l'aperçu fluide.

TRANSITION — « Cela n'a pas marché du premier coup. »

QUESTIONS PROBABLES
– « Et si le polygone n'a pas quatre sommets ? » → rectangle englobant minimal, avec une pénalité de score ×0,85.
– « Pourquoi le terme 1/r dans le score ? » → pour qu'une carte vue à 90° ne soit pas pénalisée.
""")

# ===========================================================================
# 7 - Difficulté
# ===========================================================================
s = new_slide()
chrome(s, 8, "Conception")
title(s, "Sur fond clair, la détection échouait ; médiane, CLAHE et réglage des seuils l'ont corrigée")
colsx = [ML, ML + 4.15, ML + 8.3]
heads = [("SYMPTÔME", "Carte claire sur table blanche : détection souvent en échec, alors qu'elle marchait sur fond sombre."),
         ("DEUX CAUSES", None),
         ("TROIS CORRECTIFS", None)]
for xi, (h1, body) in zip(colsx, heads):
    text(s, xi, 2.05, 3.8, 0.35, h1, size=13, bold=True, color=BLUE)
for xi in colsx[1:]:
    line(s, xi - 0.25, 2.05, xi - 0.25, 5.6, color=RULE, lw=0.75)
text(s, colsx[0], 2.5, 3.7, 1.7, heads[0][1], size=20)
for k, (bg, card, edge, cap) in enumerate([(RGBColor(0x2B, 0x31, 0x3A), WHITE, WHITE, "fond sombre : bord net"),
                                           (RGBColor(0xF1, 0xF3, 0xF5), RGBColor(0xFA, 0xFB, 0xFC), RGBColor(0xE4, 0xE8, 0xEC), "fond clair : bord faible")]):
    bx = colsx[0] + k * 1.9
    box(s, bx, 4.3, 1.75, 1.05, fill=bg, line=RULE if k else None, lw=0.75)
    cc = box(s, bx + 0.32, 4.46, 1.11, 0.70, fill=card, line=edge, lw=1.0, shape=MSO_SHAPE.ROUNDED_RECTANGLE)
    cc.adjustments[0] = 0.08
    text(s, bx, 5.4, 1.75, 0.3, cap, size=12, color=MUTED, align=PP_ALIGN.CENTER)
_m = mark(s)
text(s, colsx[1], 2.5, 3.75, 3.2, [
    [{"t": "Bug : ", "bold": True, "color": NAVY}, "seuils de Canny calculés sur la ", {"t": "moyenne", "bold": True}, " et non sur la médiane : trop hauts dès que la scène est claire."],
    [{"t": "Contraste local", "bold": True, "color": NAVY}, " trop faible entre la carte et le fond."],
], size=18, spacing=14)
step(s, since(s, _m))
_m = mark(s)
text(s, colsx[2], 2.5, 3.75, 3.2, [
    [{"t": "1  ", "bold": True, "color": BLUE}, "seuils dérivés de la vraie médiane"],
    [{"t": "2  ", "bold": True, "color": BLUE}, "passe CLAHE avant la détection"],
    [{"t": "3  ", "bold": True, "color": BLUE}, "réglage des seuils de score et d'aire du quadrilatère"],
], size=18, spacing=14)
step(s, since(s, _m))
_m = mark(s)
box(s, ML, 5.85, CW, 0.75, fill=PANEL)
text(s, ML + 0.25, 5.85, CW - 0.5, 0.75, [[{"t": "Résultat observé : ", "bold": True, "color": NAVY},
     "taux de détection comparable sur fond clair et sur fond sombre."]], size=18, anchor=MSO_ANCHOR.MIDDLE)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 3 clics : 1) les deux causes ; 2) les trois correctifs ; 3) le résultat observé."
notes(s, """
⏱ 0:40 (cumul 4:40)

TEXTE ORAL
Sur fond clair, une table blanche par exemple, la détection échouait souvent. [clic] Deux causes : un bug, les seuils de Canny calculés sur la moyenne au lieu de la médiane, donc trop hauts sur une scène claire ; et un contraste local trop faible. [clic] Trois correctifs : la vraie médiane, un CLAHE avant la détection, et le réglage des seuils de score et d'aire. [clic] Résultat : une détection comparable sur fond clair et sur fond sombre.

TRANSITION — « Une fois la carte trouvée, quand capturer ? »

QUESTION PROBABLE
– « Lequel des correctifs a le plus compté ? » → je ne l'ai pas isolé ; une étude d'ablation sur un jeu d'images fixe serait la bonne méthode. Le gradient morphologique a été ajouté pour le même cas extrême, en dernier recours.
""")

# ===========================================================================
# 8 - Autocapture
# ===========================================================================
s = new_slide()
chrome(s, 9, "Conception")
title(s, "La capture part seule après deux frames consécutives nettes, bien exposées et stables", w=9.2)
_u = mark(s)
states = ["searching", "poorQuality", "holding", "triggerCapture", "captured"]
nw, ng, ny, nh = 1.48, 0.45, 2.45, 0.62
nx = [ML + i * (nw + ng) for i in range(5)]
for i, st in enumerate(states):
    hl = st == "holding"
    box(s, nx[i], ny, nw, nh, fill=PANEL if not hl else WHITE, line=BLUE if hl else RULE, lw=2.0 if hl else 1.0)
    text(s, nx[i], ny, nw, nh, st, size=12, bold=True, color=NAVY, font=MONO, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    if i < 4:
        line(s, nx[i] + nw + 0.03, ny + nh / 2, nx[i + 1] - 0.03, ny + nh / 2, color=NAVY, lw=1.5, arrow=True)
fw = ["carte trouvée", "contrôles OK", "2 frames OK", ""]
for i, lab in enumerate(fw[:3]):
    text(s, nx[i] + nw + ng / 2 - 0.65, ny - 0.32, 1.3, 0.28, lab, size=11, color=MUTED, align=PP_ALIGN.CENTER)
# retours
def back(i_from, i_to, depth, lab):
    xa = nx[i_from] + nw / 2
    xb = nx[i_to] + nw / 2
    yb_ = ny + nh + depth
    line(s, xa, ny + nh, xa, yb_, color=MUTED, lw=1.0)
    line(s, xa, yb_, xb, yb_, color=MUTED, lw=1.0)
    line(s, xb, yb_, xb, ny + nh + 0.02, color=MUTED, lw=1.0, arrow=True)
    text(s, min(xa, xb) + 0.1, yb_ + 0.03, abs(xa - xb) - 0.2, 0.3, lab, size=12, color=MUTED, align=PP_ALIGN.CENTER)
back(2, 1, 0.28, "un contrôle échoue")
back(4, 0, 0.72, "face suivante, ou échec de la capture → reset")
unit(s, since(s, _u))
_m = mark(s)
rowsq = [("Netteté", "variance du Laplacien, après CLAHE, ≥ 120 (à 856 × 540 px)"),
         ("Luminosité", "moyenne dans [60 ; 225] et ≤ 12 % de pixels ≥ 250"),
         ("Stabilité", "dérive des coins ≤ 2,5 % de la diagonale, sur 3 frames"),
         ("Contenu", "la face attendue est reconnue (diapositive suivante)"),
         ("Maintien", "2 frames consécutives : un compteur, pas une minuterie")]
for i, (k, v) in enumerate(rowsq):
    yy = 4.3 + i * 0.5
    text(s, ML, yy, 1.8, 0.5, k, size=18, bold=True, color=NAVY)
    text(s, ML + 1.85, yy + 0.02, 7.2, 0.55, v, size=16, color=INK)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 1 clic : les cinq contrôles, après avoir décrit la machine à états."
pic = picture(s, A("ecran_recto_guidage.png"), 10.25, 1.9, h=4.55, alt="Écran recto réel : cadre-guide et message « Ne bougez plus… » ; données masquées")
text(s, 10.25, 6.5, 2.55, 0.42, "Écran réel : message de qualité « Ne bougez plus… »", size=12, color=MUTED)
notes(s, """
⏱ 0:45 (cumul 5:25)

TEXTE ORAL
L'autocapture est une machine à états : searching tant qu'aucune carte n'est trouvée, poorQuality tant qu'un contrôle échoue, holding pendant le maintien, puis triggerCapture et captured. Si un contrôle échoue, on revient en arrière. [clic] Cinq contrôles : la netteté, mesurée par la variance du Laplacien, au moins 120 ; la luminosité, avec au plus 12 % de pixels saturés pour écarter les reflets ; la stabilité, une dérive des coins sous 2,5 % de la diagonale ; la bonne face ; et un maintien de deux images consécutives. C'est un compteur d'images, pas une minuterie.

TRANSITION — « La bonne face, justement. »

QUESTIONS PROBABLES
– « Pourquoi 120 ? » → seuil empirique, valable seulement à la résolution de redressement 856 × 540 ; à une autre résolution la variance change (rapport §5.2.1).
– « Pourquoi ≈ 2 s mesurées si deux frames suffisent ? » → à environ 10 analyses par seconde, les compteurs (3 frames de stabilité, 2 de maintien) ne représentent qu'une fraction de seconde ; le reste vient de la confirmation des signaux de contenu et du geste de l'utilisateur. Je ne l'ai pas décomposé finement : c'est un chronométrage manuel.
""")

# ===========================================================================
# 9 - Recto / verso
# ===========================================================================
s = new_slide()
chrome(s, 10, "Conception")
title(s, "Un visage et deux gabarits identifient le recto ; trois indices votent pour le verso")
ph = 4.1
_side = []
for k, (img, lab, hd, lines_, xo) in enumerate([
    ("ecran_recto_guidage.png", "Recto", "RECTO", [
        [{"t": "Visage : ", "bold": True, "color": NAVY}, "cascade de Haar standard d'OpenCV, pré-entraînée, testée sur 4 rotations (échelle 1,05, 8 voisins) : elle donne aussi l'orientation."],
        [{"t": "Logo + drapeau : ", "bold": True, "color": NAVY}, "template matching, corrélation ≥ 0,6, CLAHE sur gabarit et région."],
    ], ML),
    ("ecran_verso_guidage.png", "Verso", "VERSO", [
        [{"t": "Code-barres : ", "bold": True, "color": NAVY}, "localisé, non décodé."],
        [{"t": "Empreinte : ", "bold": True, "color": NAVY}, "variance du Laplacien dans [150 ; 4 000]."],
        [{"t": "Ligne de séparation : ", "bold": True, "color": NAVY}, "Hough probabiliste, bas de la carte."],
        [{"t": "Vote ", "bold": True, "color": NAVY}, "sur 4 rotations : la mieux soutenue gagne."],
    ], ML + 6.2)]):
    _m = mark(s)
    picture(s, A(img), xo, 2.0, h=ph, alt=f"Écran {lab} : silhouettes de guidage de l'application ; données masquées")
    pw = ph * 715 / 1280
    text(s, xo + pw + 0.3, 2.0, 0.0 + 5.9 - pw - 0.3, 0.35, hd, size=13, bold=True, color=BLUE)
    text(s, xo + pw + 0.3, 2.45, 5.9 - pw - 0.4, 3.6, lines_, size=16, spacing=10)
    _side.append(since(s, _m))
# gabarits réels
_m = mark(s)
tx = ML + ph * 715 / 1280 + 0.3
picture(s, os.path.join(REPO, "assets", "templates", "logo.png"), tx, 5.25, h=0.75, alt="Gabarit de référence : logo")
picture(s, os.path.join(REPO, "assets", "templates", "flag.png"), tx + 0.75, 5.25, h=0.55, alt="Gabarit de référence : drapeau")
text(s, tx + 1.75, 5.25, 2.0, 0.75, "gabarits de référence embarqués", size=12, color=MUTED, anchor=MSO_ANCHOR.MIDDLE)
step(s, _side[0] + since(s, _m))
step(s, _side[1])
_m = mark(s)
box(s, ML, 6.25, CW, 0.5, fill=PANEL)
text(s, ML + 0.25, 6.25, CW - 0.5, 0.5, [[{"t": "Anti-doublon : ", "bold": True, "color": NAVY},
     "après le recto, seule une face qui réunit les trois indices du verso peut déclencher la capture."]], size=16, anchor=MSO_ANCHOR.MIDDLE)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 3 clics : 1) le recto ; 2) le verso ; 3) l'anti-doublon."
text(s, ML, 6.78, 8, 0.2, "", size=4)
notes(s, """
⏱ 0:40 (cumul 6:05)

TEXTE ORAL
[clic] Au recto, la photo est toujours en haut à gauche : j'y cherche un visage avec la cascade de Haar d'OpenCV, pré-entraînée, sur quatre rotations, ce qui donne aussi l'orientation. Le logo et le drapeau sont confirmés par template matching, avec une corrélation d'au moins 0,6. [clic] Le verso n'a pas de visage : le code-barres, la texture de l'empreinte et la ligne de séparation, trouvée par une transformée de Hough, votent sur quatre rotations. [clic] Ainsi, présenter deux fois le recto ne déclenche rien.

TRANSITION — « Après la capture, l'utilisateur garde la main. »

QUESTION PROBABLE
– « Haar est-il robuste pour une photo d'identité ? » → c'est une cascade générique de visage de face ; elle suffit ici car la région est petite et fixe, mais je n'ai pas mesuré son rappel séparément.
""")

# ===========================================================================
# 10 - Parcours utilisateur
# ===========================================================================
s = new_slide()
chrome(s, 11, "Résultats")
title(s, "Après les deux captures, l'utilisateur vérifie, ajuste et exporte chaque face")
flow = [("Recto, puis verso", "capturés seuls, traités sur l'appareil"),
        ("Vérification", "contraste, netteté, mode scan (N&B)"),
        ("Ajustement", "recadrage par les coins, rotation de 90°"),
        ("Export", "galerie : recto, verso et page A4"),
        ("Historique", "consultation, partage, suppression")]
for i, (h1, d) in enumerate(flow):
    yy = 2.05 + i * 0.9
    text(s, ML, yy, 0.45, 0.5, str(i + 1), size=22, bold=True, color=BLUE)
    text(s, ML + 0.5, yy, 4.1, 0.8, [[{"t": h1, "bold": True, "color": NAVY}], d], size=16, color=INK)
shots = [("ecran_verification.png", "Vérification, amélioration", 720 / 1610),
         ("ecran_ajuster.png", "Recadrage du verso", 720 / 1610),
         ("ecran_detail_page_a4.png", "Page A4 à 300 dpi", 715 / 1600)]
hh = 4.5
x = 5.35
for img, cap, ratio in shots:
    _m = mark(s)
    w_ = hh * ratio
    picture(s, A(img), x, 1.95, h=hh, alt=cap + " ; données masquées")
    text(s, x, 1.95 + hh + 0.08, w_ + 0.3, 0.3, cap, size=12, color=MUTED)
    step(s, since(s, _m))
    x += w_ + 0.42
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 3 clics : une capture d'écran par clic (vérification, recadrage, page A4)."
notes(s, """
⏱ 0:25 (cumul 6:30)

TEXTE ORAL
Une fois les deux faces capturées, l'utilisateur [clic] vérifie et règle contraste et netteté, [clic] ajuste le recadrage si besoin, [clic] puis exporte le recto, le verso et une page A4 à 300 dpi. Tout est traité sur l'appareil.

TRANSITION — « Voyons tout le parcours en vidéo. »

QUESTIONS PROBABLES
– « Où vont les images exportées ? » → dans la galerie de l'appareil ; à partir de là, elles suivent la vie normale des photos (sauvegarde cloud, partage) : l'utilisateur doit en être informé (rapport §7.2.4).
– « Qu'est-ce qu'Avatar-ID reçoit ? » → deux images (Uint8List) et, le cas échéant, la page d'impression : le module est une brique autonome (rapport §8.2.5).
""")

# ===========================================================================
# 11 - Démonstration (vidéo)
# ===========================================================================
s = new_slide()
chrome(s, 12, "Résultats")
title(s, "Démonstration : de la carte posée devant la caméra à la page A4")
DEMO = A("demo.mp4")
fh = 4.55
fw = (fh - 0.24) * 715 / 1280 + 0.24
fx, fy = ML + 0.3, 1.95
if os.path.exists(DEMO):
    fw = fh * 720 / 1280
    mv = s.shapes.add_movie(DEMO, I(fx), I(fy), I(fw), I(fh), poster_frame_image=A("demo_poster.png"), mime_type="video/mp4")
    mv.line.color.rgb = NAVY
    mv.line.width = Pt(1.5)
    mv._element.nvPicPr.cNvPr.set("descr", "Vidéo de démonstration ; données personnelles masquées")
    AUTOPLAY.append((s.slide_id, mv.shape_id))
else:
    phone = box(s, fx, fy, fw, fh, fill=PANEL, line=NAVY, lw=2.0, shape=MSO_SHAPE.ROUNDED_RECTANGLE)
    phone.adjustments[0] = 0.08
    picture(s, A("ecran_recto_guidage.png"), fx + 0.12, fy + 0.12, h=fh - 0.24, alt="Aperçu : écran recto (à remplacer par la vidéo de démonstration)")
    text(s, fx, fy + fh + 0.08, fw + 1.5, 0.3, "Vidéo à insérer ici (Insertion → Vidéo)", size=12, color=ORANGE, bold=True)
cues = [("1", "Cadre rouge, puis vert", "la carte est détectée, la qualité est guidée"),
        ("2", "Recto puis verso, capturés seuls", "sans aucun bouton"),
        ("3", "Vérification et ajustement", "contraste, netteté, recadrage"),
        ("4", "Export", "recto, verso et page A4")]
for i, (n, h1, d) in enumerate(cues):
    yy = 2.15 + i * 1.08
    text(s, 4.9, yy, 0.5, 0.6, n, size=26, bold=True, color=BLUE)
    text(s, 5.45, yy + 0.02, 7.2, 0.9, [[{"t": h1, "bold": True, "color": NAVY}], d], size=18, color=INK)
notes(s, """
⏱ 0:45 (cumul 7:15)

VIDÉO — 40 s, muette, démarre automatiquement à l'arrivée sur la diapositive (données masquées). Pour l'intégrer : déposer le fichier dans build/assets/demo.mp4 puis relancer le script, ou dans PowerPoint : Insertion → Vidéo → Cet appareil, à la place du cadre, puis Lecture → Démarrer « Automatiquement ».

TEXTE ORAL
Voici le module en action. [lancer la vidéo] Le cadre est rouge tant que la carte n'est pas détectée, puis passe au vert ; les messages guident l'utilisateur. Le recto est capturé tout seul dès que la netteté, la luminosité et la stabilité sont bonnes, puis l'application passe au verso et le capture à son tour. On arrive ensuite sur la vérification, l'ajustement et l'export de la page A4.

TRANSITION — « Comment l'ai-je validé ? »
""")

# ===========================================================================
# 11 - Tests automatisés
# ===========================================================================
s = new_slide()
chrome(s, 13, "Résultats")
title(s, "177 cas de test automatisés passent sans échec, organisés en quatre paliers")
text(s, ML, 2.1, 4.6, 1.0, "177 / 177", size=60, bold=True, color=NAVY)
text(s, ML, 3.2, 4.6, 0.7, ["cas de test réussis · 0 échec", "flutter test, en 16 secondes"], size=18, color=INK)
text(s, ML, 4.35, 4.4, 1.6, [[{"t": "Domaine pur → tests rapides : ", "bold": True, "color": NAVY},
     "la séparation en couches (diapositive 6) permet de tester la logique sans caméra ni émulateur."]], size=16, color=INK)
xb0 = 5.9
text(s, xb0, 2.05, 6.8, 0.35, "QUATRE PALIERS, SELON CE DONT LE TEST A BESOIN", size=13, bold=True, color=BLUE)
tiers = [("A", "Logique pure Dart", "machine à états, décision de capture, stabilité"),
         ("B", "Plateforme simulée (mocktail)", "caméra, permissions, stockage, chargement de la cascade"),
         ("C", "OpenCV réel, images synthétiques", "géométrie du quad, rotation, luminosité, empreinte"),
         ("D", "Cartes réelles, sur téléphone", "visage, code-barres, empreinte, ligne, parcours complet")]
for i, (t, h1, d) in enumerate(tiers):
    _m = mark(s)
    yy = 2.55 + i * 1.0
    box(s, xb0, yy + 0.05, 0.55, 0.55, fill=NAVY if t != "D" else BLUE)
    text(s, xb0, yy + 0.05, 0.55, 0.55, t, size=20, bold=True, color=WHITE, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    text(s, xb0 + 0.8, yy, 6.0, 0.9, [[{"t": h1, "bold": True, "color": NAVY}], d], size=16, color=INK)
    step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 4 clics : un palier de test par clic (A, B, C, D)."
notes(s, """
⏱ 0:25 (cumul 7:40)

TEXTE ORAL
177 tests automatisés passent sans échec, répartis en quatre paliers : [clic] la logique pure Dart, [clic] la plateforme simulée avec mocktail, [clic] OpenCV réel sur images synthétiques, [clic] et les vraies cartes sur téléphone, avec un protocole manuel.

TRANSITION — « Et sur appareil réel ? »

QUESTIONS PROBABLES (préparation, ne pas lire)
– « Combien de fichiers de test ? » → 28 fichiers (15 A, 6 B, 7 C) ; la dernière campagne en a exécuté 21, pour 177 cas réussis. Les autres sont à relancer avec flutter test --reporter expanded.
– « Quelle couverture ? » → elle n'a pas été mesurée ; flutter test --coverage le permet directement.
""")

# ===========================================================================
# 12 - Mesures
# ===========================================================================
s = new_slide()
chrome(s, 14, "Résultats")
title(s, "Les trois cibles du cahier des charges sont atteintes sur appareil réel")
hdr = ["Mesuré", "Cible", "Ce qui est mesuré", ""]
xs = [ML, ML + 3.0, ML + 5.6, ML + 10.6]
ws = [2.9, 2.5, 4.8, CW - 10.6]
for h1, xi, wi in zip(hdr, xs, ws):
    text(s, xi, 2.05, wi, 0.35, h1.upper(), size=13, bold=True, color=BLUE)
data = [("92–100 ms", "< 100 ms par image", "temps de traitement d'une frame dans l'isolate, horodaté avant/après"),
        ("92 %", "≥ 90 %, conditions normales", "recto/verso bien reconnus, protocole manuel sur cartes réelles"),
        ("≈ 2 s", "≈ 2 s", "délai chronométré entre le cadre stabilisé et le déclenchement de la capture")]
for i, (m, c, w_) in enumerate(data):
    _m = mark(s)
    yy = 2.55 + i * 1.3
    line(s, ML, yy - 0.08, SW - ML, yy - 0.08, color=RULE, lw=0.75)
    text(s, xs[0], yy, ws[0], 1.0, m, size=38, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
    text(s, xs[1], yy, ws[1], 1.0, c, size=18, color=INK, anchor=MSO_ANCHOR.MIDDLE)
    text(s, xs[2], yy, ws[2], 1.0, w_, size=16, color=INK, anchor=MSO_ANCHOR.MIDDLE)
    text(s, xs[3], yy, ws[3], 1.0, "Atteinte", size=16, bold=True, color=BLUE, anchor=MSO_ANCHOR.MIDDLE)
    step(s, since(s, _m))
line(s, ML, 2.55 + 3 * 1.3 - 0.08, SW - ML, 2.55 + 3 * 1.3 - 0.08, color=RULE, lw=0.75)
_m = mark(s)
box(s, ML, 6.15, CW, 0.55, fill=PANEL)
text(s, ML + 0.25, 6.15, CW - 0.5, 0.55, [[{"t": "Android et iOS : ", "bold": True, "color": NAVY},
     "le même pipeline OpenCV tourne sur les deux plateformes, avec le même comportement."]], size=16, anchor=MSO_ANCHOR.MIDDLE)
ANIM[s.slide_id][-1] += since(s, _m)
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 3 clics : une mesure par clic (temps, reconnaissance, délai) ; Android et iOS arrive avec la troisième."
notes(s, """
⏱ 0:30 (cumul 8:10)

TEXTE ORAL
Les trois cibles sont atteintes : [clic] 92 à 100 millisecondes de traitement par image dans l'isolate, [clic] 92 % de recto/verso reconnus sur cartes réelles, [clic] et environ deux secondes entre le cadre stabilisé et la capture, avec le même comportement sur Android et iOS.

TRANSITION — « Pour la suite. »

QUESTIONS PROBABLES (préparation, ne pas lire)
– « Sur quel téléphone, combien d'essais ? » → donner vos notes d'essais (modèles Android et iOS, nombre de cartes).
– « 92–100 ms, c'est la latence de bout en bout ? » → non : c'est le traitement dans l'isolate ; l'aperçu reste fluide car les frames reçues pendant un traitement sont ignorées.
– « Pourquoi ≈ 2 s si deux frames suffisent ? » → à environ dix analyses par seconde, les compteurs (3 frames de stabilité, 2 de maintien) ne font qu'une fraction de seconde ; le reste vient de la confirmation des signaux de contenu et du geste de l'utilisateur.
""")

# ===========================================================================
# 13 - Perspectives
# ===========================================================================
s = new_slide()
chrome(s, 15, "Bilan")
title(s, "Quatre pistes pour amener le module vers la production")
lims = [("Jeu d'images", "constituer un jeu de CIN plus large pour affiner les seuils et, à terme, ajouter un modèle appris."),
        ("Tests réels", "automatiser le palier D avec des images de référence (visage, code-barres, empreinte, ligne)."),
        ("Timeout", "prévenir l'utilisateur quand aucune carte n'est détectée après un certain délai."),
        ("Anti-fraude carte", "analyser la texture pour repérer une carte affichée sur un écran, en amont de la vivacité d'Avatar-ID.")]
for i, (k, v) in enumerate(lims):
    _m = mark(s)
    yy = 2.15 + i * 1.0
    box(s, ML, yy + 0.12, 0.14, 0.56, fill=BLUE)
    text(s, ML + 0.4, yy, 2.4, 0.8, k, size=20, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
    text(s, ML + 2.95, yy, CW - 2.95, 0.8, v, size=20, color=INK, anchor=MSO_ANCHOR.MIDDLE)
    if i < 3:
        line(s, ML + 0.4, yy + 0.92, SW - ML, yy + 0.92, color=RULE, lw=0.5)
    step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 4 clics : une piste par clic."
notes(s, """
⏱ 0:20 (cumul 8:30)

TEXTE ORAL
Quatre pistes vers la production : [clic] un jeu d'images plus large, [clic] des tests réels automatisés, [clic] un message de timeout, [clic] et une analyse de texture contre les cartes affichées sur un écran.

TRANSITION — « Pour conclure. »

QUESTIONS PROBABLES (préparation, ne pas lire)
– « Une photo d'écran passe-t-elle ? » → les contrôles (capture en direct, deux faces, qualité) réduisent fortement ce risque ; la vivacité de la personne est ensuite vérifiée par Avatar-ID ; une analyse de texture de la carte renforcerait encore la chaîne.
""")

# ===========================================================================
# 14 - Conclusion
# ===========================================================================
s = new_slide()
chrome(s, 16, "Bilan")
title(s, "Une capture recto/verso autonome, sur Android et iOS, livrée en six semaines")
colz = [("LIVRÉ", ["Détection : 4 passes et un score", "Autocapture : 4 contrôles, 2 frames", "Recto/verso et anti-doublon",
                   "Vérification, page A4, export, historique"]),
        ("MESURÉ", ["92–100 ms par image", "92 % de recto/verso reconnus", "≈ 2 s jusqu'à la capture",
                    "177 tests réussis · Android et iOS"]),
        ("PERSPECTIVES", ["Jeu d'images élargi", "Tests réels automatisés", "Message de timeout", "Anti-fraude sur la carte"])]
wcol = (CW - 2 * 0.5) / 3
for i, (h1, items_) in enumerate(colz):
    _m = mark(s)
    xi = ML + i * (wcol + 0.5)
    line(s, xi, 2.15, xi + wcol, 2.15, color=NAVY if i < 2 else BLUE, lw=3.0)
    text(s, xi, 2.3, wcol, 0.4, h1, size=14, bold=True, color=NAVY if i < 2 else BLUE)
    text(s, xi, 2.8, wcol, 2.6, items_, size=18, color=INK, spacing=10)
    step(s, since(s, _m))
_m = mark(s)
text(s, ML, 5.3, CW, 1.4, [
    [{"t": "Mon apport : ", "bold": True, "color": NAVY},
     "l'enchaînement des passes et le score du quadrilatère, l'isolate, la machine à états, le vote recto/verso et le post-traitement, autour des primitives d'OpenCV."],
    [{"t": "Ce que j'en retiens : ", "bold": True, "color": NAVY},
     "un choix technologique se justifie par les contraintes réelles d'un projet."]], size=16, color=INK, spacing=8)
step(s, since(s, _m))
ANIM_NOTE[s.slide_id] = "ANIMATIONS — 4 clics : 1) livré ; 2) mesuré ; 3) perspectives ; 4) mon apport."
notes(s, """
⏱ 0:35 (cumul 9:05)

TEXTE ORAL
En résumé, [clic] j'ai livré un module complet en six semaines, [clic] qui atteint ses trois cibles sur Android et iOS, [clic] avec des pistes claires pour la suite. [clic] Mon apport, c'est tout ce qui entoure les primitives d'OpenCV : l'enchaînement des passes, le score, l'isolate, la machine à états et le vote recto/verso. J'en retiens qu'un choix technique se justifie par les contraintes réelles du projet.

TRANSITION — « Merci de votre attention. »
""")

# ===========================================================================
# 15 - Merci
# ===========================================================================
s = new_slide()
chrome(s, 17)
x0 = ML
for name, hh in (("logo_manouba.png", 0.78), ("logo_ensi.png", 0.78), ("logo_codingaholic.png", 0.62)):
    p = picture(s, A(name), x0, 0.55 + (0.78 - hh), h=hh, alt=name.replace("logo_", "Logo ").replace(".png", ""), frame=False)
    x0 += p.width / 914400 + 0.35
text(s, ML, 2.55, 7.6, 1.6, "Merci pour votre attention", size=48, bold=True, color=NAVY, name="Titre")
text(s, ML, 4.25, 7.4, 0.5, "Je suis à votre disposition pour vos questions.", size=22, color=BLUE)
text(s, ML, 5.25, 7.6, 0.9, [[{"t": "Mohammed Amine Chaieb", "bold": True, "color": NAVY, "size": 20}],
     "Détection automatique et autocapture de la CIN tunisienne · Avatar-ID"], size=16, color=MUTED, spacing=4)
card_outline(s, 8.55, 2.35, 4.15)
notes(s, """
⏱ 0:05 (cumul 9:10)

TEXTE ORAL
Merci de votre attention ; je suis à votre disposition pour vos questions.

PENDANT LES QUESTIONS — revenir si besoin à la diapositive 16 (bilan) ; secours A à D après cette diapositive : A seuils, B méthodes de test, C sécurité et confidentialité, D apport personnel et références.
""")

# ===========================================================================
# Secours A - Seuils
# ===========================================================================
s = new_slide()
chrome(s, 18, backup="A")
title(s, "Tous les seuils sont empiriques ; la netteté 120 n'a de sens qu'à 856 × 540 px")
params = [("Score de détection minimal", "0,30"), ("Sortie anticipée", "0,65"), ("Réduction, recherche pleine image", "0,45"),
          ("Marge de recherche suivie", "20 %"), ("Canny bas / haut (× médiane)", "0,66 / 1,33"), ("Aire de contour minimale", "3,5 %"),
          ("Aire maximale acceptée", "75 %"), ("Pénalité quad non net", "× 0,85"), ("Proportion / taille (score)", "0,8 / 0,2"),
          ("Redressement", "856 × 540 px"), ("Netteté minimale (Laplacien)", "120"), ("Luminosité moyenne", "[60 ; 225]"),
          ("Pixels saturés tolérés (≥ 250)", "12 %"), ("Dérive de coin maximale", "2,5 % diag."), ("Frames stables / reset", "3 / 2"),
          ("Frames de maintien", "2"), ("Haar : échelle / voisins", "1,05 / 8"), ("Corrélation logo / drapeau", "0,6"),
          ("Variance empreinte", "[150 ; 4 000]"), ("Netteté post-traitement (a)", "0,6")]
half = 10
for c in range(2):
    xo = ML + c * (CW / 2 + 0.15)
    for i, (k, v) in enumerate(params[c * half:(c + 1) * half]):
        yy = 1.95 + i * 0.46
        if i % 2 == 0:
            box(s, xo, yy, CW / 2 - 0.15, 0.46, fill=PANEL)
        text(s, xo + 0.12, yy, CW / 2 - 2.0, 0.46, k, size=15, color=INK, anchor=MSO_ANCHOR.MIDDLE)
        text(s, xo + CW / 2 - 2.0, yy, 1.7, 0.46, v, size=15, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE, align=PP_ALIGN.RIGHT)
notes(s, """
SECOURS A — à ouvrir seulement si le jury interroge les seuils.
Tous ont été fixés par réglage empirique sur les échantillons de CIN disponibles (rapport §5.5). Le seuil de netteté 120 est calibré sur l'image redressée de 856 × 540 px : à une autre résolution, la variance du Laplacien change et le seuil n'est plus valable. Aucune analyse de sensibilité n'a été faite : c'est une perspective naturelle une fois un jeu d'images constitué.
""")

# ===========================================================================
# Secours B - Méthodes de test
# ===========================================================================
s = new_slide()
chrome(s, 19, backup="B")
title(s, "Chaque composant a sa méthode de test, de la logique pure au téléphone réel")
rowsb = [["Composant", "Méthode de test", "Palier"],
         ["Flux caméra", "test sur téléphone réel : ni lag ni coupure", "manuel"],
         ["Détection de la carte", "géométrie pure, images synthétiques, échantillons à différents angles", "A · C · D"],
         ["Netteté et luminosité", "images volontairement floues, sombres ou surexposées", "C"],
         ["Stabilité", "dérive simulée légère, puis franche", "A"],
         ["Recto/verso", "mélange d'images recto et verso", "D"],
         ["Autocapture", "bout en bout : délai et absence de faux déclenchement", "A · B · D"],
         ["Recadrage", "comparaison visuelle : aucun bord coupé", "C · D"],
         ["Anti-doublon", "même face présentée deux fois", "D"],
         ["Gestion des erreurs", "carte cachée, permission caméra refusée", "B · D"],
         ["Test global", "recto puis verso, plusieurs téléphones et éclairages", "D"]]
tb = s.shapes.add_table(len(rowsb), 3, I(ML), I(1.95), I(CW), I(4.75)).table
for j, wv in enumerate([3.2, CW - 4.8, 1.6]):
    tb.columns[j].width = I(wv)
for i, r in enumerate(rowsb):
    tb.rows[i].height = I(0.43)
    for j, v in enumerate(r):
        cell = tb.cell(i, j)
        cell.fill.solid()
        cell.fill.fore_color.rgb = PANEL if i == 0 or i % 2 == 0 else WHITE
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
        cell.margin_top = cell.margin_bottom = I(0.02)
        cell.margin_left = I(0.12)
        tf = cell.text_frame
        tf.text = ""
        p = tf.paragraphs[0]
        run = p.add_run()
        run.text = v
        run.font.size = Pt(15)
        run.font.name = FONT
        run.font.bold = i == 0 or j == 0
        run.font.color.rgb = NAVY if (i == 0 or j in (0, 2)) else INK
tp = s.shapes[-1]._element.graphic.graphicData.tbl.tblPr
tp.set("firstRow", "0")
tp.set("bandRow", "0")
for st in tp.findall(qn("a:tableStyleId")):
    tp.remove(st)
notes(s, """
SECOURS B — méthodes de test (rapport, tableau 9.3).
Paliers : A logique pure Dart, B plateforme simulée (mocktail), C OpenCV réel sur images synthétiques, D cartes réelles sur appareil (manuel).
Si l'on vous demande le détail : 28 fichiers de test (15 A, 6 B, 7 C) ; la dernière campagne a exécuté 177 cas, tous réussis.
""")

# ===========================================================================
# Secours C - Sécurité et confidentialité
# ===========================================================================
s = new_slide()
chrome(s, 20, backup="C")
title(s, "La capture est sûre par construction ; la vivacité est vérifiée ensuite par Avatar-ID")
wv2 = (CW - 0.6) / 2
text(s, ML, 2.0, wv2, 0.35, "GARANTI PAR CONSTRUCTION", size=13, bold=True, color=BLUE)
text(s, ML, 2.5, wv2, 3.4, ["Capture en direct, depuis le flux caméra", "Deux faces distinctes, dans l'ordre recto → verso",
                             "Qualité contrôlée : netteté, luminosité, stabilité", "Traitement sur l'appareil, sans service tiers"],
     size=18, spacing=12)
xo = ML + wv2 + 0.6
line(s, xo - 0.3, 2.0, xo - 0.3, 5.6, color=RULE, lw=0.75)
text(s, xo, 2.0, wv2, 0.35, "EN AVAL ET PROCHAINES ÉTAPES", size=13, bold=True, color=NAVY)
text(s, xo, 2.5, wv2, 3.4, ["Vivacité et comparaison des photos : Avatar-ID", "Analyse de texture contre les cartes sur écran",
                            "Informer l'utilisateur lors de l'export en galerie", "Chiffrement des captures stockées"],
     size=18, spacing=12)
box(s, ML, 5.85, CW, 0.62, fill=PANEL)
text(s, ML + 0.25, 5.85, CW - 0.5, 0.62, [[{"t": "Données de test : ", "bold": True, "color": NAVY},
     "les captures montrées dans cette soutenance sont masquées dans les pixels (photo, nom, numéros, code-barres)."]],
     size=16, anchor=MSO_ANCHOR.MIDDLE)
notes(s, """
SECOURS C — sécurité et confidentialité.
Les contrôles (capture en direct, deux faces, qualité) réduisent fortement le risque de photo d'écran ou d'image préparée ; la vivacité de la personne et la comparaison des photos sont réalisées ensuite par Avatar-ID ; une analyse de texture de la carte reste une piste (rapport §7.2.4). Les images exportées en galerie suivent ensuite la vie normale des photos (sauvegarde cloud, partage). Chiffrement : non traité pendant le stage.
""")

# ===========================================================================
# Secours D - Apport personnel et références
# ===========================================================================
s = new_slide()
chrome(s, 21, backup="D")
title(s, "OpenCV fournit les primitives ; l'assemblage, les scores et la logique de capture sont développés")
wl = 7.3
text(s, ML, 1.95, 3.5, 0.35, "FOURNI (OPENCV, PLUGINS)", size=13, bold=True, color=MUTED)
text(s, ML, 2.4, 3.4, 4.2, ["Canny, seuillage adaptatif, Otsu", "CLAHE, morphologie", "findContours, approxPolyDP",
                             "warpPerspective", "Laplacien, HoughLinesP", "BarcodeDetector", "cascade de Haar pré-entraînée",
                             "matchTemplate", "camera, gal, image"], size=14, color=INK, spacing=3)
text(s, ML + 3.65, 1.95, 3.7, 0.35, "DÉVELOPPÉ PENDANT LE STAGE", size=13, bold=True, color=BLUE)
text(s, ML + 3.65, 2.4, 3.7, 4.2, ["conversion YUV420/BGRA → Mat", "DocumentContourDetector : passes, sortie, suivi",
                                    "CardQuadGeometry : score", "DetectionIsolateWorker", "StabilityTracker, stabilisateur",
                                    "machine à états d'autocapture", "BackOrientationDetector : vote", "CardImageEnhancer, page A4",
                                    "écrans, historique, export"], size=14, color=INK, spacing=3)
line(s, ML + wl + 0.15, 1.95, ML + wl + 0.15, 6.5, color=RULE, lw=0.75)
xr = ML + wl + 0.45
text(s, xr, 1.95, CW - wl - 0.45, 0.35, "RÉFÉRENCES", size=13, bold=True, color=BLUE)
refs = ["Canny, IEEE TPAMI, 1986", "Otsu, IEEE TSMC, 1979", "Zuiderveld, CLAHE, Graphics Gems IV, 1994",
        "Viola & Jones, CVPR, 2001", "Matas et al., Hough probabiliste, CVIU, 2000", "Hartley & Zisserman, 2004",
        "Martin, Clean Architecture, 2017", "ISO/IEC 7810:2019 (ID-1)", "Google ML Kit, Document Scanner API [15]"]
text(s, xr, 2.4, CW - wl - 0.45, 4.2, refs, size=13, color=INK, spacing=4)
notes(s, """
SECOURS D — « Qu'avez-vous développé vous-même ? » et références.
OpenCV fournit les opérateurs ; j'ai conçu leur enchaînement (quatre passes, sortie anticipée, suivi, garde-fous), le score géométrique, l'architecture en isolate, la stabilisation, la machine à états et la décision d'autocapture, le vote sur quatre rotations du verso, le post-traitement et la page A4, ainsi que les écrans. Les références sont celles de la bibliographie du rapport.
""")

_apply_animations()
prs.save(OUT)
print("OK", os.path.abspath(OUT), len(prs.slides._sldIdLst), "diapositives")
