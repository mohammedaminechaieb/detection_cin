import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Statut de luminosité d'une frame par rapport aux bornes acceptables.
enum BrightnessStatus { tooDark, ok, tooBright }

/// Contrôle de luminosité de la carte déjà recadrée (voir l'appelant :
/// `classify` est appelé sur `warped`, pas sur la frame entière).
///
/// This used to be a single global mean-brightness check, and that was
/// a second, independent way "doesn't work on light surfaces" showed
/// up - separate from the contour-detection issue fixed in
/// `DocumentContourDetector`. Even once the border *was* correctly
/// found, a light/white ID card naturally pushes the mean of the
/// warped card region well above a fixed ceiling just by being a
/// light-colored object - nothing to do with the frame being
/// genuinely overexposed or unreadable. That was getting flagged
/// `tooBright` and blocking autocapture regardless.
///
/// The actual thing worth guarding against - a blown-out glare
/// hotspot off the card's plastic lamination - looks different from
/// "the card is light-colored": it's a small, fully-saturated patch,
/// not a moderately-elevated overall mean. So this now checks both,
/// separately: `meanBrightness` for genuinely dark/overexposed scenes,
/// and [classify]'s highlight-fraction check for real localized glare,
/// rather than using one number to try to represent both.
class BrightnessDetector {
  const BrightnessDetector();

  static const double kMinMeanBrightness = 60.0;

  // Raised from 205. See the class doc: this ceiling was rejecting
  // legitimately bright/white cards, not just genuinely overexposed
  // frames. 225 still catches a frame that's washed out overall; actual
  // glare is now caught by `kMaxHighlightFraction` below instead of
  // being folded into this one threshold.
  static const double kMaxMeanBrightness = 225.0;

  // If at least this fraction of the card's pixels are (near-)fully
  // saturated, treat it as real glare (a reflection off the
  // lamination), independent of what the mean brightness says - a
  // small hotspot can sit on top of an otherwise perfectly readable
  // card without moving the mean much at all, and conversely a big,
  // evenly bright white card can have almost no fully-saturated pixels
  // even though its mean is high.
  static const double kMaxHighlightFraction = 0.12;
  static const double kHighlightPixelValue = 250;

  cv.Mat _toGray(cv.Mat mat) => mat.channels == 1 ? mat : cv.cvtColor(mat, cv.COLOR_BGR2GRAY);

  /// Intensité moyenne (0-255) de [mat].
  double meanBrightness(cv.Mat mat) {
    final gray = _toGray(mat);
    final scalar = cv.mean(gray);
    if (!identical(gray, mat)) gray.dispose();
    return scalar.val1;
  }

  /// Fraction (0.0-1.0) of [gray]'s pixels that are at or above
  /// [kHighlightPixelValue] - i.e. blown out / fully saturated.
  double _highlightFraction(cv.Mat gray) {
    final (_, mask) = cv.threshold(gray, kHighlightPixelValue, 255, cv.THRESH_BINARY);
    final highlightPixels = cv.countNonZero(mask);
    mask.dispose();
    final totalPixels = gray.rows * gray.cols;
    if (totalPixels == 0) return 0.0;
    return highlightPixels / totalPixels;
  }

  BrightnessStatus classify(cv.Mat mat) {
    final gray = _toGray(mat);
    final brightness = cv.mean(gray).val1;
    final highlightFraction = _highlightFraction(gray);
    if (!identical(gray, mat)) gray.dispose();

    if (brightness < kMinMeanBrightness) return BrightnessStatus.tooDark;
    if (highlightFraction > kMaxHighlightFraction) return BrightnessStatus.tooBright;
    if (brightness > kMaxMeanBrightness) return BrightnessStatus.tooBright;
    return BrightnessStatus.ok;
  }
}