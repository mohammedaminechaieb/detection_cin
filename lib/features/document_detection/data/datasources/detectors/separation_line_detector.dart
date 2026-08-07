import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Detects the horizontal separation line printed across the bottom of
/// the card's back, combining a saturation-gradient edge map with a
/// standard Canny edge map before running a probabilistic Hough transform.
class SeparationLineDetector {
  const SeparationLineDetector();

  static const double _defaultMinLengthRatio = 0.5;
  static const double _maxAngleFromHorizontalDegrees = 10;
  static const int _houghThreshold = 80;
  static const double _houghMaxLineGap = 10;
  static const double _cannyLowerThreshold = 50;
  static const double _cannyUpperThreshold = 150;

  (bool, (int, int, int, int)?, double) detect(
    cv.Mat orientedCard, {
    double minLengthRatio = _defaultMinLengthRatio,
  }) {
    final w = orientedCard.cols;

    final hsv = cv.cvtColor(orientedCard, cv.COLOR_BGR2HSV);
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

    final gray = cv.cvtColor(orientedCard, cv.COLOR_BGR2GRAY);
    final grayEdges = cv.canny(gray, _cannyLowerThreshold, _cannyUpperThreshold);
    gray.dispose();

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
        bestLine = (x1, y1, x2, y2);
      }
    }

    if (bestLine == null) return (false, null, 0.0);

    final lengthRatio = bestLength / w;
    final found = lengthRatio >= minLengthRatio;
    return (found, bestLine, lengthRatio);
  }
}
