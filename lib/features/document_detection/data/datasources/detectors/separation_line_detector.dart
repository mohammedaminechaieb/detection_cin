import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../../../shared/utils/histogram_utils.dart';

/// Detects the horizontal separation line printed across the bottom of
/// the card's back, combining a saturation-gradient edge map with a
/// standard Canny edge map before running a probabilistic Hough transform.
///
/// Restricted to [bottomRegionRatio] of the card's height: the line only
/// ever appears near the bottom, and running Hough over the *whole* card
/// let plenty of other horizontal-ish edges (text baselines, the photo's
/// edge, the barcode's border) compete with and sometimes outscore the
/// real line, especially when the card is otherwise clean (a strong false
/// candidate elsewhere out-lengths the true one). Cropping first also
/// keeps the y-coordinates of any candidate line implicitly close to the
/// actual line, since they're offset back into full-card coordinates
/// before returning.
class SeparationLineDetector {
  const SeparationLineDetector();

  // Lowered from 0.5: a genuinely faint printed line (small gradient, not
  // black-on-white) breaks up into shorter Hough segments even with the
  // tophat/blackhat feature mask below, since low-contrast stretches of
  // it fall right at the mask's own noise floor. 0.45 still rejects
  // short unrelated horizontal edges (text baselines are much shorter
  // relative to the card width), it just stops discarding a real line
  // that Hough only recovered in slightly-less-than-full-width pieces.
  static const double _defaultMinLengthRatio = 0.45;
  static const double _maxAngleFromHorizontalDegrees = 10;
  // Lowered from 80: a faint line contributes fewer edge-pixel "votes"
  // per unit length to the Hough accumulator than a high-contrast one,
  // even after the tophat/blackhat local-contrast pass - 80 was tuned
  // against strong black/white edges and was silently rejecting faint
  // lines that never accumulated enough votes to be returned as a
  // candidate at all, regardless of length. Combined with the stricter
  // horizontal-angle and length-ratio checks, and the temporal
  // stabilizer downstream, this doesn't meaningfully open the door to
  // false positives - it just lets weaker-but-real lines register.
  static const int _houghThreshold = 60;
  // Raised from 10: bridges the small gaps a faint line tends to leave
  // in its own edge mask (a few pixels here and there sitting just under
  // the local threshold), so Hough can still merge it into one long
  // segment instead of several short ones that individually fail
  // `minLengthRatio`.
  static const double _houghMaxLineGap = 16;

  // Was fixed at 50/150: fine in good light, but under dim/poor lighting
  // a low-contrast region produces far fewer edges at a fixed absolute
  // threshold, while the saturation-gradient path (Otsu-thresholded, see
  // below) self-adapts fine - so the Canny half of the combined edge map
  // was disproportionately weak exactly when detection needs to be most
  // robust. Median-derived thresholds (same "0.66x / 1.33x median"
  // heuristic already used in DocumentContourDetector, for consistency)
  // scale down with the scene instead of staying fixed.
  static const double _cannyLowerMedianFactor = 0.66;
  static const double _cannyUpperMedianFactor = 1.33;

  /// Fraction of the card's height, measured up from the bottom edge,
  /// that the search is restricted to.
  static const double _defaultBottomRegionRatio = 0.35;

  // Keep only the top 3% of tophat/blackhat responses as "line" pixels.
  // See the comment where this is used for why a percentile (not Otsu)
  // is the right threshold here.
  static const double _lineFeaturePercentile = 0.97;

  (bool, (int, int, int, int)?, double) detect(
    cv.Mat orientedCard, {
    double minLengthRatio = _defaultMinLengthRatio,
    double bottomRegionRatio = _defaultBottomRegionRatio,
  }) {
    final w = orientedCard.cols;
    final h = orientedCard.rows;

    final regionHeight = (h * bottomRegionRatio).round().clamp(1, h);
    final regionY0 = h - regionHeight;
    final region = orientedCard.region(cv.Rect(0, regionY0, w, regionHeight));

    final hsv = cv.cvtColor(region, cv.COLOR_BGR2HSV);
    final channels = cv.split(hsv);
    hsv.dispose();
    final saturation = channels[1];
    channels[0].dispose();
    channels[2].dispose();

    final blurredSat = cv.gaussianBlur(saturation, (5, 5), 0);
    saturation.dispose();

    final gradY = cv.sobel(blurredSat, cv.MatType.CV_32F, 0, 1, ksize: 3);
    blurredSat.dispose();
    final absGradY = cv.convertScaleAbs(gradY);
    gradY.dispose();

    final (_, colorEdges) = cv.threshold(absGradY, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
    absGradY.dispose();

    final gray = cv.cvtColor(region, cv.COLOR_BGR2GRAY);
    // Was `cv.meanStdDev(gray).$1` mislabeled as "median" - that's the
    // MEAN, not the median, and the two can diverge enough on a
    // skewed-brightness region (e.g. a mostly-light card back with a
    // dark barcode block) to meaningfully shift where the Canny
    // thresholds land. Real median via histogram, matching the same fix
    // in DocumentContourDetector._median (see that file for the fuller
    // explanation of why this matters on bright scenes specifically).
    final median = histogramMedian(gray);
    var cannyLower = math.max(0, _cannyLowerMedianFactor * median).toDouble();
    var cannyUpper = math.min(255, _cannyUpperMedianFactor * median).toDouble();
    cannyLower = math.min(cannyLower, 90.0);
    cannyUpper = math.max(cannyUpper, 60.0);
    final grayEdges = cv.canny(gray, cannyLower, cannyUpper);

    // Canny and the saturation-gradient pass above both threshold against
    // a *global* statistic of the region (the median, the Otsu split).
    // The real printed separation line on a CIN back is often a genuinely
    // faint, low-contrast rule - not "white on black" - so its actual
    // gradient can sit below whatever global threshold either of those
    // passes settles on, while some *other* unrelated horizontal edge
    // (a text baseline, the barcode's own border) has enough contrast to
    // clear it instead. That's the reported symptom: "detects any line,
    // not the real one, because it's tuned for high contrast."
    //
    // Top-hat/black-hat with a wide, flat, 1px-tall horizontal kernel
    // finds thin features by comparing each pixel only to its *local*
    // neighbourhood along that kernel, not to a global statistic - so a
    // faint line still stands out against its immediate surroundings
    // even when the region as a whole is low-contrast. This is the
    // standard technique for isolating thin line/rule features
    // independent of overall scene contrast.
    final lineKernelWidth = math.max(15, (w * 0.05).round());
    final lineKernel = cv.getStructuringElement(cv.MORPH_RECT, (lineKernelWidth, 1));
    final tophat = cv.morphologyEx(gray, cv.MORPH_TOPHAT, lineKernel);
    final blackhat = cv.morphologyEx(gray, cv.MORPH_BLACKHAT, lineKernel);
    final lineFeature = cv.bitwiseOR(tophat, blackhat);
    tophat.dispose();
    blackhat.dispose();
    // Was Otsu-thresholded here - which is the wrong tool for this
    // specific job. Otsu assumes a roughly bimodal histogram and finds
    // the split between its two humps; a real separation line only ever
    // covers a couple of percent of the bottom-region's pixels, so its
    // (real, but small) response sits as a thin tail on an otherwise
    // near-unimodal "background texture" histogram - Otsu tends to
    // fold that tail into "background" rather than isolate it,
    // especially the fainter that tail is. That's the reported
    // "small gradient change is not detected" symptom surviving even
    // after the tophat/blackhat fix: the *feature map* was already
    // finding the faint line, the *threshold* on top of it was then
    // discarding it anyway.
    //
    // A percentile threshold sidesteps that assumption entirely: it
    // just keeps the top `1 - kLineFeaturePercentile` of responses,
    // whatever their absolute value, which is exactly what "isolate the
    // sparse strongest-local-contrast pixels" needs. Floored at 12 so a
    // genuinely flat/textureless region (no line and little noise, low
    // percentile response) doesn't threshold at ~0 and mark everything
    // as a line.
    final percentileThreshold = math.max(12.0, histogramPercentile(lineFeature, _lineFeaturePercentile));
    final (_, lineMask) = cv.threshold(lineFeature, percentileThreshold, 255, cv.THRESH_BINARY);
    lineFeature.dispose();

    gray.dispose();
    region.dispose();

    final combined = cv.bitwiseOR(colorEdges, grayEdges);
    colorEdges.dispose();
    grayEdges.dispose();
    final edges = cv.bitwiseOR(combined, lineMask);
    combined.dispose();
    lineMask.dispose();

    final linesMat = cv.HoughLinesP(
      edges,
      1,
      3.14159265 / 180,
      _houghThreshold,
      minLineLength: (w * minLengthRatio).toDouble(),
      maxLineGap: _houghMaxLineGap,
    );
    edges.dispose();

    (int, int, int, int)? bestLine;
    double bestLength = 0;

    final linesList = linesMat.toList();
    linesMat.dispose();

    for (final line in linesList) {
      final x1 = (line[0]).toInt();
      final y1 = (line[1]).toInt();
      final x2 = (line[2]).toInt();
      final y2 = (line[3]).toInt();

      final dx = (x2 - x1).toDouble();
      final dy = (y2 - y1).toDouble();
      final length = math.sqrt(dx * dx + dy * dy);

      final angle = (math.atan2(dy, dx) * 180 / math.pi).abs();
      final isHorizontal = angle < _maxAngleFromHorizontalDegrees ||
          angle > (180 - _maxAngleFromHorizontalDegrees);

      if (isHorizontal && length > bestLength) {
        bestLength = length;
        // Offset y back into the original (uncropped) card's coordinates.
        bestLine = (x1, y1 + regionY0, x2, y2 + regionY0);
      }
    }

    if (bestLine == null) return (false, null, 0.0);

    final lengthRatio = bestLength / w;
    final found = lengthRatio >= minLengthRatio;
    return (found, bestLine, lengthRatio);
  }

  // The median/percentile histogram helpers that used to live here as
  // `_median`/`_percentile` (near-duplicates of `DocumentContourDetector`'s
  // own copies) are now `histogramMedian`/`histogramPercentile` in
  // `shared/utils/histogram_utils.dart`.
}