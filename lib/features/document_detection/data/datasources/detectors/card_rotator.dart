import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Rotates a card image by a fixed number of degrees (0/90/180/270),
/// as determined by [FaceOrientationDetector]'s face search.
class CardRotator {
  const CardRotator();

  /// Returns a new rotated Mat, or - for [degrees] values with no
  /// rotation to apply (i.e. 0) - the same [image] instance passed in.
  /// Callers must not unconditionally dispose the result: check
  /// `identical(result, image)` first, or the source Mat will be
  /// double-freed.
  cv.Mat apply(cv.Mat image, int degrees) {
    switch (degrees) {
      case 90:
        return cv.rotate(image, cv.ROTATE_90_CLOCKWISE);
      case 180:
        return cv.rotate(image, cv.ROTATE_180);
      case 270:
        return cv.rotate(image, cv.ROTATE_90_COUNTERCLOCKWISE);
      default:
        return image;
    }
  }
}
