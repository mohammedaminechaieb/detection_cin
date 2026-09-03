// Tier C helper (see test/README.md). Builds small synthetic cv.Mat
// images in-memory so detector tests (blur/brightness/geometry/warp/
// rotate) don't need any bundled fixture image files - just opencv_dart's
// native binary for the host platform.
//
// ASSOMPTION NON VÉRIFIÉE: cv.Mat/cv.rectangle/cv.line/cv.randn call
// shapes below match opencv_dart's current API (same caveat as
// blur_detector.dart / brightness_detector.dart already carry). Adjust
// against the pinned version in pubspec.yaml if `flutter analyze` flags
// any of these.
import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// A flat, mid-gray BGR image with no texture at all - the "obviously
/// blurry" / "flat" case for sharpness tests.
cv.Mat flatMat({int width = 400, int height = 300, int gray = 180}) {
  return cv.Mat.fromScalar(height, width, cv.MatType.CV_8UC3, cv.Scalar.all(gray.toDouble()));
}

/// A high-frequency checkerboard - the "obviously sharp" case for
/// sharpness tests. Cell size controls frequency; smaller cells score
/// higher on a Laplacian-variance sharpness check.
cv.Mat checkerboardMat({
  int width = 400,
  int height = 300,
  int cell = 10,
  int darkValue = 40,
  int lightValue = 220,
}) {
  final mat = cv.Mat.zeros(height, width, cv.MatType.CV_8UC3);
  for (var y = 0; y < height; y += cell) {
    for (var x = 0; x < width; x += cell) {
      final isDark = ((x ~/ cell) + (y ~/ cell)).isEven;
      final value = isDark ? darkValue : lightValue;
      cv.rectangle(
        mat,
        cv.Rect(x, y, cell, cell),
        cv.Scalar.all(value.toDouble()),
        thickness: -1, // filled
      );
    }
  }
  return mat;
}

/// A uniformly-bright image, for the "too bright" / highlight-fraction
/// brightness tests. [highlightFraction] of the image (top-left block)
/// is pushed to near-white to simulate a glare hotspot independent of
/// the base brightness.
cv.Mat brightMat({
  int width = 400,
  int height = 300,
  int baseValue = 235,
  double highlightFraction = 0.0,
  int highlightValue = 253,
}) {
  final mat = cv.Mat.fromScalar(height, width, cv.MatType.CV_8UC3, cv.Scalar.all(baseValue.toDouble()));
  if (highlightFraction > 0) {
    final highlightArea = (width * height * highlightFraction).round();
    final side = math.sqrt(highlightArea).round().clamp(1, math.min(width, height)).toInt();
    cv.rectangle(
      mat,
      cv.Rect(0, 0, side, side),
      cv.Scalar.all(highlightValue.toDouble()),
      thickness: -1,
    );
  }
  return mat;
}

/// A uniformly-dark image, for the "too dark" brightness test.
cv.Mat darkMat({int width = 400, int height = 300, int value = 20}) {
  return cv.Mat.fromScalar(height, width, cv.MatType.CV_8UC3, cv.Scalar.all(value.toDouble()));
}

/// A synthetic "card" - a lighter rectangle centered on a darker
/// background, roughly at the CIN aspect ratio - for contour/quad tests
/// that need something with an actual edge to find.
cv.Mat syntheticCardMat({
  int width = 856,
  int height = 540,
  int marginFraction10 = 1, // ~10% margin on each side
}) {
  final mat = cv.Mat.fromScalar(height, width, cv.MatType.CV_8UC3, cv.Scalar.all(40));
  final marginX = (width * marginFraction10 / 10).round();
  final marginY = (height * marginFraction10 / 10).round();
  cv.rectangle(
    mat,
    cv.Rect(marginX, marginY, width - 2 * marginX, height - 2 * marginY),
    cv.Scalar.all(230),
    thickness: -1,
  );
  return mat;
}

/// Frees a list of Mats, ignoring already-disposed ones. Handy in
/// `tearDown` when a test creates several intermediate Mats.
void disposeAll(Iterable<cv.Mat?> mats) {
  for (final m in mats) {
    m?.dispose();
  }
}
