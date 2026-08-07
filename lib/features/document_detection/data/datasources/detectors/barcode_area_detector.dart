import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Detects whether a barcode occupies a plausible fraction of the card's
/// back-side image (rather than just decoding its contents, which the
/// app doesn't need).
class BarcodeAreaDetector {
  cv.BarcodeDetector? _detector;

  (bool, double) detect(cv.Mat orientedCard) {
    final detector = _detector ??= cv.BarcodeDetector.empty();
    final (found, points) = detector.detect(orientedCard);

    if (!found || points.length < 4) return (false, 0.0);

    final cardArea = (orientedCard.rows * orientedCard.cols).toDouble();
    double bestRatio = 0.0;

    for (var i = 0; i + 3 < points.length; i += 4) {
      final quad = [points[i], points[i + 1], points[i + 2], points[i + 3]];
      double area = 0;
      for (var j = 0; j < 4; j++) {
        final p1 = quad[j];
        final p2 = quad[(j + 1) % 4];
        area += p1.x * p2.y - p2.x * p1.y;
      }
      area = area.abs() / 2.0;

      final ratio = area / cardArea;
      if (ratio > bestRatio) bestRatio = ratio;
    }

    return (bestRatio > 0, bestRatio);
  }

  void dispose() {
    _detector?.dispose();
    _detector = null;
  }
}
