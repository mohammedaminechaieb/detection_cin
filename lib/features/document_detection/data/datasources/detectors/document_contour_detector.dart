import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../domain/entities/detected_document.dart';
import 'card_quad_geometry.dart';

/// Minimum combined aspect-ratio/size score (see [CardQuadGeometry.quadScore])
/// for a candidate quad to be accepted as a real detection.
///
/// Lowered from 0.35: even after the CLAHE/median-Canny fixes below, a
/// light card on a light background still produces a slightly noisier
/// quad (softer corners, a bit more aspect-ratio error) than a
/// high-contrast one - it was landing at ~0.30-0.35 and getting rejected
/// right at the old cutoff. This isn't accepting "no edge" candidates,
/// it's accepting slightly-imperfect-but-real ones; false positives are
/// still filtered by `DetectionStabilizer` requiring 3 consecutive
/// confirming frames before the UI (or autocapture) treats the border as
/// actually detected.
const double kMinDetectionScore = 0.30;

class _Candidate {
  final CardQuad quad;
  final double score;
  final String source;
  _Candidate(this.quad, this.score, this.source);
}

/// Finds the card's quad in a camera frame and tracks it across frames.
///
/// Detection runs in two modes:
/// - **Full-frame search** ([_detectFullFrame]): used when there's no
///   tracked quad yet. Downscales the frame for a cheap coarse pass, then
///   re-detects at full resolution inside a margin around the coarse hit.
/// - **Tracked search** ([_detectAroundTrackedQuad]): used once a quad has
///   been found, searching only a small margin around the previous
///   frame's quad. Much cheaper than a full-frame search and avoids
///   frame-to-frame jitter.
class DocumentContourDetector {
  DocumentContourDetector({CardQuadGeometry? geometry}) : _geometry = geometry ?? const CardQuadGeometry();

  final CardQuadGeometry _geometry;
  CardQuad? _trackedQuad;

  static final _kernel5 = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
  static final _kernel9 = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
  static final _kernel15 = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));

  // If a candidate scores at least this well, later (more expensive)
  // candidate-generation passes are skipped for that frame.
  static const double _earlyExitScore = 0.65;

  // Coarse full-frame search downscales by this factor before its first
  // pass, purely for speed - the resulting quad is scaled back up and
  // re-detected at full resolution within a margin around it.
  //
  // This is the actual reason detection worked on dark backgrounds but
  // not light/white ones: a light card on a light surface only ever
  // produces a *weak* gradient at its border to begin with, and
  // downscaling to 30% averages pixels together, which softens - and on
  // an already-weak edge, can erase - exactly that gradient before Canny
  // ever runs. A strong dark-background edge has enough margin to
  // survive that softening; a light-on-light edge often doesn't. Since
  // `_detectFullFrame` aborts immediately if this coarse pass finds
  // nothing (see below), losing the edge here means detection never even
  // reaches the more careful full-resolution pass. Raising the scale
  // keeps more of the original gradient intact, at some speed cost - this
  // path only runs while no quad is currently tracked, i.e. initial
  // acquisition or after a lost track, not every frame.
  static const double _coarseSearchScale = 0.45;
  static const double _coarseSearchMarginFraction = 0.15;
  static const double _trackedSearchMarginFraction = 0.20;

  // Canny thresholds are derived from the image's median intensity, using
  // the common "0.66x / 1.33x median" heuristic.
  static const double _cannyLowerMedianFactor = 0.66;
  static const double _cannyUpperMedianFactor = 1.33;

  // A contour must cover at least this fraction of the search area to be
  // considered as a candidate (filters out small noise/texture contours).
  //
  // Lowered from 0.05: on a light-on-light scene the border's edge map is
  // thinner and more broken up even after CLAHE, so `findContours` more
  // often returns several smaller fragments of the true border instead of
  // one clean closed contour. 0.05 was discarding fragments that were
  // still a real (if partial) piece of the card's edge before they ever
  // reached the aspect/area scoring step. 0.035 keeps those in play
  // without letting through pure noise/texture contours, which are
  // typically an order of magnitude smaller than the card itself.
  static const double _minContourAreaFraction = 0.035;

  // approxPolyDP epsilon, as a fraction of the contour's perimeter -
  // controls how aggressively the contour is simplified toward 4 corners.
  static const double _polygonApproxEpsilonFraction = 0.02;

  // A candidate quad's area must be at least this fraction of its
  // underlying contour's area, to reject quads that poorly fit the
  // contour they were derived from.
  static const double _minContourToQuadAreaRatio = 0.75;

  // Score penalty applied to quads derived from a non-clean 4-point
  // contour (i.e. approximated via a min-area rect instead).
  static const double _nonCleanQuadScorePenalty = 0.85;

  void resetTracking() {
    _trackedQuad = null;
  }

  DetectedDocument detectCard(cv.Mat image) {
    final tracked = _trackedQuad;

    if (tracked == null) {
      final result = _detectFullFrame(image);
      _trackedQuad = result.isDetected ? result.quad : null;
      return result;
    }

    final result = _detectAroundTrackedQuad(image, tracked);
    if (result == null) {
      _trackedQuad = null;
      return DetectedDocument.none();
    }

    _trackedQuad = result.quad;
    return result;
  }

  DetectedDocument _detectFullFrame(cv.Mat image) {
    final coarse = cv.resize(image, (0, 0), fx: _coarseSearchScale, fy: _coarseSearchScale);

    final coarseGray = _preprocessGrayFast(coarse);
    final coarseArea = (coarse.rows * coarse.cols).toDouble();
    final (coarseCandidates, m1, m2, m3, m4) = _findCandidates(coarseGray, coarse, coarseArea);

    coarse.dispose();
    coarseGray.dispose();
    m1.dispose();
    m2.dispose();
    m3.dispose();
    m4.dispose();

    if (coarseCandidates.isEmpty) {
      // Last resort for a scene where even the raised coarse scale above
      // still lost the border (very low light-on-light contrast): search
      // the whole frame at full resolution instead of a downscaled copy.
      // This only runs on initial acquisition/re-acquisition (no quad is
      // tracked yet at this point), not every frame, so it trades a
      // slower one-off search for actually finding the card at all.
      return _detectInCroppedRegion(image, 0, 0, image.cols, image.rows) ??
          DetectedDocument.none();
    }
    coarseCandidates.sort((a, b) => b.score.compareTo(a.score));
    final coarseBest = coarseCandidates.first;
    if (coarseBest.score < kMinDetectionScore) return DetectedDocument.none();

    final fullW = image.cols;
    final fullH = image.rows;

    final xs = [
      coarseBest.quad.topLeft.x, coarseBest.quad.topRight.x,
      coarseBest.quad.bottomRight.x, coarseBest.quad.bottomLeft.x,
    ];
    final ys = [
      coarseBest.quad.topLeft.y, coarseBest.quad.topRight.y,
      coarseBest.quad.bottomRight.y, coarseBest.quad.bottomLeft.y,
    ];

    final minX = xs.reduce(math.min) / _coarseSearchScale;
    final maxX = xs.reduce(math.max) / _coarseSearchScale;
    final minY = ys.reduce(math.min) / _coarseSearchScale;
    final maxY = ys.reduce(math.max) / _coarseSearchScale;

    final boxW = maxX - minX;
    final boxH = maxY - minY;
    final marginX = boxW * _coarseSearchMarginFraction;
    final marginY = boxH * _coarseSearchMarginFraction;

    final cropX1 = math.max(0, (minX - marginX).toInt());
    final cropY1 = math.max(0, (minY - marginY).toInt());
    final cropX2 = math.min(fullW, (maxX + marginX).toInt());
    final cropY2 = math.min(fullH, (maxY + marginY).toInt());

    return _detectInCroppedRegion(image, cropX1, cropY1, cropX2, cropY2) ??
        DetectedDocument.none();
  }

  DetectedDocument? _detectAroundTrackedQuad(cv.Mat image, CardQuad previousQuad) {
    final fullW = image.cols;
    final fullH = image.rows;

    final xs = [
      previousQuad.topLeft.x, previousQuad.topRight.x,
      previousQuad.bottomRight.x, previousQuad.bottomLeft.x,
    ];
    final ys = [
      previousQuad.topLeft.y, previousQuad.topRight.y,
      previousQuad.bottomRight.y, previousQuad.bottomLeft.y,
    ];

    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);

    final boxW = maxX - minX;
    final boxH = maxY - minY;
    final marginX = boxW * _trackedSearchMarginFraction;
    final marginY = boxH * _trackedSearchMarginFraction;

    final cropX1 = math.max(0, (minX - marginX).toInt());
    final cropY1 = math.max(0, (minY - marginY).toInt());
    final cropX2 = math.min(fullW, (maxX + marginX).toInt());
    final cropY2 = math.min(fullH, (maxY + marginY).toInt());

    return _detectInCroppedRegion(image, cropX1, cropY1, cropX2, cropY2);
  }

  DetectedDocument? _detectInCroppedRegion(
    cv.Mat image,
    int cropX1,
    int cropY1,
    int cropX2,
    int cropY2,
  ) {
    final cropW = cropX2 - cropX1;
    final cropH = cropY2 - cropY1;
    if (cropW <= 0 || cropH <= 0) return null;

    final region = image.region(cv.Rect(cropX1, cropY1, cropW, cropH));

    final gray = _preprocessGray(region);
    final regionArea = (region.rows * region.cols).toDouble();
    final (candidates, rm1, rm2, rm3, rm4) = _findCandidates(gray, region, regionArea);

    gray.dispose();
    rm1.dispose();
    rm2.dispose();
    rm3.dispose();
    rm4.dispose();
    region.dispose();

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;
    if (best.score < kMinDetectionScore) return null;

    final finalQuad = CardQuad(
      topLeft: CardPoint(best.quad.topLeft.x + cropX1, best.quad.topLeft.y + cropY1),
      topRight: CardPoint(best.quad.topRight.x + cropX1, best.quad.topRight.y + cropY1),
      bottomRight: CardPoint(best.quad.bottomRight.x + cropX1, best.quad.bottomRight.y + cropY1),
      bottomLeft: CardPoint(best.quad.bottomLeft.x + cropX1, best.quad.bottomLeft.y + cropY1),
    );

    return DetectedDocument(isDetected: true, quad: finalQuad, score: best.score, source: best.source);
  }

  cv.Mat _preprocessGray(cv.Mat image) {
    final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    final filtered = cv.bilateralFilter(gray, 9, 75, 75);
    gray.dispose();

    final clahe = cv.createCLAHE(clipLimit: 2.5, tileGridSize: (8, 8));
    final result = clahe.apply(filtered);
    filtered.dispose();

    return result;
  }

  cv.Mat _preprocessGrayFast(cv.Mat image) {
    final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    final blurred = cv.gaussianBlur(gray, (3, 3), 0);
    gray.dispose();

    // Low-contrast scenes (light card on a light/white surface) were
    // failing to produce ANY candidate at this coarse full-frame stage -
    // which gates everything, since `_detectFullFrame` aborts immediately
    // if this pass finds nothing. `_preprocessGray` (the refined,
    // per-region pass used once a quad is already tracked) already
    // applies CLAHE and handles low contrast fine - but it never got a
    // chance to run, because tracking was never established in the first
    // place. Adding CLAHE here too (skipping the heavier bilateral filter
    // to keep this pass cheap) fixes that gate.
    //
    // Clip limit raised from 2.5 to 3.5: on a light-on-light scene the
    // *local* contrast the border actually has is small even after
    // normalizing for global brightness, so a higher clip limit (more
    // aggressive local contrast boost) is needed to push that gradient
    // up into a range Canny's fixed lower/upper bounds (see
    // `_findCandidates`) can actually pick up.
    final clahe = cv.createCLAHE(clipLimit: 3.5, tileGridSize: (8, 8));
    final result = clahe.apply(blurred);
    blurred.dispose();

    return result;
  }

  /// Runs up to four candidate-generation passes (Canny, a looser Canny,
  /// adaptive threshold, and color-saturation masking), stopping early
  /// once a good-enough candidate is found. Returns the candidates found
  /// plus all four intermediate masks (empty Mats for skipped passes) -
  /// callers own and must dispose all four.
  (List<_Candidate>, cv.Mat, cv.Mat, cv.Mat, cv.Mat) _findCandidates(
      cv.Mat gray, cv.Mat bgr, double imageArea) {
    final blurred = cv.gaussianBlur(gray, (5, 5), 0);

    final median = _median(gray);
    var lower = math.max(0, (_cannyLowerMedianFactor * median)).toDouble();
    var upper = math.min(255, (_cannyUpperMedianFactor * median)).toDouble();

    // Safety clamp independent of the median/mean computation above: on
    // a very bright scene (light card, light background) even a
    // correctly-computed median can sit high enough (180-220+) that
    // `0.66x` alone is still too strict for the genuinely weak gradients
    // such a scene produces. Capping `lower` keeps Canny from ever
    // requiring more gradient strength than this, regardless of how
    // bright the frame is. Similarly, floor `upper` so a very dark
    // scene doesn't collapse the [lower, upper] window to near-nothing.
    lower = math.min(lower, 90.0);
    upper = math.max(upper, 60.0);

    final candidates = <_Candidate>[];
    final imgH = gray.rows;
    final imgW = gray.cols;

    final cannyRaw = cv.canny(blurred, lower, upper);
    final edges = cv.dilate(cannyRaw, _kernel5, iterations: 2);
    cannyRaw.dispose();

    final edgesClosed = cv.morphologyEx(edges, cv.MORPH_CLOSE, _kernel15, iterations: 2);
    final edgesClosedFin = cv.morphologyEx(edges, cv.MORPH_CLOSE, _kernel9, iterations: 1);
    edges.dispose();

    _collectCandidatesFromMask(edgesClosed, 'canny', imgW, imgH, imageArea, candidates);
    var bestSoFar = candidates.isEmpty ? 0.0 : candidates.map((c) => c.score).reduce(math.max);

    if (bestSoFar < _earlyExitScore) {
      _collectCandidatesFromMask(edgesClosedFin, 'canny_fin', imgW, imgH, imageArea, candidates);
      bestSoFar = candidates.isEmpty ? 0.0 : candidates.map((c) => c.score).reduce(math.max);
    }

    cv.Mat? threshClosed;
    if (bestSoFar < _earlyExitScore) {
      final thresh = cv.adaptiveThreshold(
        blurred,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY,
        31,
        5,
      );
      threshClosed = cv.morphologyEx(thresh, cv.MORPH_CLOSE, _kernel9);
      thresh.dispose();

      _collectCandidatesFromMask(threshClosed, 'adaptive', imgW, imgH, imageArea, candidates);
      bestSoFar = candidates.isEmpty ? 0.0 : candidates.map((c) => c.score).reduce(math.max);
    }

    cv.Mat? satMask;
    if (bestSoFar < _earlyExitScore) {
      final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
      final channels = cv.split(hsv);
      hsv.dispose();

      final saturation = channels[1];
      channels[0].dispose();
      channels[2].dispose();

      final (_, satMaskRaw) = cv.threshold(saturation, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
      saturation.dispose();
      satMask = cv.morphologyEx(satMaskRaw, cv.MORPH_CLOSE, _kernel15, iterations: 2);
      satMaskRaw.dispose();

      _collectCandidatesFromMask(satMask, 'couleur', imgW, imgH, imageArea, candidates);
      bestSoFar = candidates.isEmpty ? 0.0 : candidates.map((c) => c.score).reduce(math.max);
    }

    // Last-resort pass, specifically for a card and its background that
    // are nearly the same gray level even after CLAHE: every pass above
    // still measures contrast against some *global* statistic somewhere
    // (Canny's median-derived thresholds, Otsu's global histogram split
    // for both the adaptive-threshold-derived and saturation masks) - on
    // a true light-on-light scene the edge can survive as only a couple
    // of gray levels of difference, below what any of those global
    // thresholds will register as "an edge" at all. `MORPH_GRADIENT`
    // (dilate-erode, evaluated per-pixel against its own local
    // neighborhood) responds to a difference that small regardless of
    // the frame's overall brightness - the same principle the
    // tophat/blackhat fix in `SeparationLineDetector` already relies on
    // for the same underlying problem. Otsu on the *gradient image*
    // (not the raw frame) then separates "this pixel sits on some edge"
    // from "this pixel doesn't", which remains a meaningful split even
    // when the raw pixel values on either side of that edge are close.
    cv.Mat? morphGradMask;
    if (bestSoFar < _earlyExitScore) {
      final gradKernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      final morphGrad = cv.morphologyEx(blurred, cv.MORPH_GRADIENT, gradKernel);
      final (_, morphGradMaskRaw) =
          cv.threshold(morphGrad, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
      morphGrad.dispose();
      morphGradMask = cv.morphologyEx(morphGradMaskRaw, cv.MORPH_CLOSE, _kernel9, iterations: 2);
      morphGradMaskRaw.dispose();

      _collectCandidatesFromMask(morphGradMask, 'gradient_morpho', imgW, imgH, imageArea, candidates);
    }
    morphGradMask?.dispose();

    blurred.dispose();

    return (
      candidates,
      edgesClosed,
      edgesClosedFin,
      threshClosed ?? cv.Mat.empty(),
      satMask ?? cv.Mat.empty(),
    );
  }

  void _collectCandidatesFromMask(
    cv.Mat mask,
    String maskName,
    int imgW,
    int imgH,
    double imageArea,
    List<_Candidate> candidates,
  ) {
    final (contours, _) = cv.findContours(mask, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    final sorted = contours.toList()
      ..sort((a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)));
    final top10 = sorted.take(10);

    for (final c in top10) {
      final area = cv.contourArea(c);
      if (area < _minContourAreaFraction * imageArea) continue;

      final perimeter = cv.arcLength(c, true);
      final approx = cv.approxPolyDP(c, _polygonApproxEpsilonFraction * perimeter, true);

      CardQuad quad;
      bool isCleanQuad;
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        final pts = approx.map((p) => cv.Point2f(p.x.toDouble(), p.y.toDouble())).toList();
        quad = _geometry.orderPoints(pts);
        isCleanQuad = true;
      } else {
        final rect = cv.minAreaRect(c);
        final box = cv.boxPoints(rect);
        final pts = box.map((p) => cv.Point2f(p.x, p.y)).toList();
        quad = _geometry.orderPoints(pts);
        isCleanQuad = false;
      }

      final fittedArea = _geometry.quadArea(quad);
      if (fittedArea <= 0) continue;
      if (area / fittedArea < _minContourToQuadAreaRatio) continue;

      if (_geometry.touchesFrameBorder(quad, imgW, imgH)) continue;

      var score = _geometry.quadScore(quad, area, imageArea);
      if (!isCleanQuad) score *= _nonCleanQuadScorePenalty;

      candidates.add(_Candidate(quad, score, maskName));
    }
  }

  double _median(cv.Mat gray) {
    // NOTE: this used to call `cv.meanStdDev(gray)` and return the MEAN,
    // mislabeled as median - that's a real bug, not just a naming slip.
    // On a bright/white scene (light card on a light background), the
    // mean is high (e.g. ~220/255), so `0.66x/1.33x` of it pushed the
    // Canny thresholds up into a range so high that only very strong
    // gradients survived - exactly the opposite of what a low-contrast
    // light-on-light scene needs (weak gradients everywhere, by
    // definition). That's why light-surface detection regressed instead
    // of improving: the "adaptive" threshold was adapting the wrong way
    // on bright scenes. A true median (via histogram) is far less
    // sensitive to being dragged up by a mostly-bright frame than the
    // mean is, and is also the statistic the "0.66x/1.33x" heuristic is
    // actually defined against (see the common OpenCV auto-Canny recipe
    // this was following).
    final hist = cv.calcHist(
      cv.VecMat.fromList([gray]),
      cv.VecI32.fromList([0]),
      cv.Mat.empty(),
      cv.VecI32.fromList([256]),
      cv.VecF32.fromList([0,256]),
    );
    final totalPixels = gray.rows * gray.cols;
    final halfPixels = totalPixels / 2;

    var cumulative = 0.0;
    for (var bin = 0; bin < 256; bin++) {
      cumulative += hist.at<double>(bin, 0);
      if (cumulative >= halfPixels) {
        hist.dispose();
        return bin.toDouble();
      }
    }
    hist.dispose();
    return 128.0;
  }
}