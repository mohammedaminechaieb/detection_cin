import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Detects whether a barcode occupies a plausible fraction of the card's
/// back-side image (rather than just decoding its contents, which the
/// app doesn't need).
class BarcodeAreaDetector {
  cv.BarcodeDetector? _detector;

  // The barcode sits in the top portion of a right-side-up CIN back
  // (same layout `SeparationLineDetector`/`FingerprintPresenceDetector`
  // assume - barcode top, fingerprint bottom-right, separated by the
  // line). This matters beyond just "is there a barcode": OpenCV's
  // `BarcodeDetector` actually localizes the barcode, which means it
  // finds the same physical barcode regardless of the image's rotation -
  // a real barcode reader has to be rotation-tolerant to be useful at
  // all. That made `barcodeFound` alone identical across all 4 rotation
  // candidates in `BackOrientationDetector`'s search, contributing
  // nothing to *which* rotation is correct despite being counted as one
  // of only 3 votes - which was a real, direct cause of the back
  // consistently landing on the wrong orientation (the search was
  // effectively deciding between just fingerprint-texture and
  // separation-line, both weaker/less specific signals, since barcode
  // agreed with every candidate equally). Checking *where* the localized
  // barcode ended up, not just whether one was found, turns this into
  // the single most reliable orientation signal available (a real
  // barcode is a far more distinctive, lower-false-positive-rate feature
  // than "some texture in a variance band" or "some horizontal line").
  static const double _expectedTopRegionFraction = 0.45;

  /// Returns (found, areaRatio, isInExpectedPosition). [isInExpectedPosition]
  /// is only meaningful when [found] is true.
  (bool, double, bool) detect(cv.Mat orientedCard) {
    final detector = _detector ??= cv.BarcodeDetector.empty();
    final (found, points) = detector.detect(orientedCard);

    if (!found || points.length < 4) return (false, 0.0, false);

    final cardArea = (orientedCard.rows * orientedCard.cols).toDouble();
    final cardHeight = orientedCard.rows.toDouble();
    double bestRatio = 0.0;
    bool bestInPosition = false;

    for (var i = 0; i + 3 < points.length; i += 4) {
      final quad = [points[i], points[i + 1], points[i + 2], points[i + 3]];
      double area = 0;
      double centroidY = 0;
      for (var j = 0; j < 4; j++) {
        final p1 = quad[j];
        final p2 = quad[(j + 1) % 4];
        area += p1.x * p2.y - p2.x * p1.y;
        centroidY += p1.y;
      }
      area = area.abs() / 2.0;
      centroidY /= 4;

      final ratio = area / cardArea;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        bestInPosition = centroidY <= cardHeight * _expectedTopRegionFraction;
      }
    }

    return (bestRatio > 0, bestRatio, bestInPosition);
  }

  void dispose() {
    _detector?.dispose();
    _detector = null;
  }
}
