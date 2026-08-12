import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

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

  static const double _defaultMinLengthRatio = 0.5;
  static const double _maxAngleFromHorizontalDegrees = 10;
  static const int _houghThreshold = 80;
  static const double _houghMaxLineGap = 10;

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
    final median = _median(gray);
    var cannyLower = math.max(0, _cannyLowerMedianFactor * median).toDouble();
    var cannyUpper = math.min(255, _cannyUpperMedianFactor * median).toDouble();
    cannyLower = math.min(cannyLower, 90.0);
    cannyUpper = math.max(cannyUpper, 60.0);
    final grayEdges = cv.canny(gray, cannyLower, cannyUpper);
    gray.dispose();
    region.dispose();

    final edges = cv.bitwiseOR(colorEdges, grayEdges);
    colorEdges.dispose();
    grayEdges.dispose();

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

  double _median(cv.Mat gray) {
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