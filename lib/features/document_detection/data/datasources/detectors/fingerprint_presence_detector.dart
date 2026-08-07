import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Detects whether the fingerprint area on the card's back has an actual
/// fingerprint texture, using the variance of the Laplacian as a
/// texture-richness signal: too smooth (blank) or too noisy (smudged/glare)
/// both fall outside the expected [minVariance, maxVariance] band.
class FingerprintPresenceDetector {
  const FingerprintPresenceDetector();

  // Region of interest as fractions of the card's width/height, matching
  // where the fingerprint sits on a right-side-up CIN back.
  static const double _roiX1Fraction = 0.55;
  static const double _roiY1Fraction = 0.55;
  static const double _roiX2Fraction = 0.95;
  static const double _roiY2Fraction = 0.95;

  static const double _defaultMinVariance = 150;
  static const double _defaultMaxVariance = 4000;

  (bool, double) detect(
    cv.Mat orientedCard, {
    double minVariance = _defaultMinVariance,
    double maxVariance = _defaultMaxVariance,
  }) {
    final gray = cv.cvtColor(orientedCard, cv.COLOR_BGR2GRAY);
    final w = gray.cols;
    final h = gray.rows;

    final roi = gray.region(cv.Rect(
      (_roiX1Fraction * w).toInt(),
      (_roiY1Fraction * h).toInt(),
      ((_roiX2Fraction - _roiX1Fraction) * w).toInt(),
      ((_roiY2Fraction - _roiY1Fraction) * h).toInt(),
    ));

    final laplacian = cv.laplacian(roi, cv.MatType.CV_64F);
    final (_, stddev) = cv.meanStdDev(laplacian);
    final variance = stddev.val1 * stddev.val1;

    laplacian.dispose();
    roi.dispose();
    gray.dispose();

    final found = variance >= minVariance && variance <= maxVariance;
    return (found, variance);
  }
}
