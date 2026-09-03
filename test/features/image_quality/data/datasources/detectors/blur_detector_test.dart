// Tier C - needs opencv_dart's native binary, no device required, uses
// synthetic in-memory Mats. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:detection_cin/features/image_quality/data/datasources/detectors/blur_detector.dart';

import '../../../../../test_helpers/mat_test_utils.dart';

void main() {
  const detector = BlurDetector();

  group('BlurDetector.sharpnessScore', () {
    test('a flat, textureless image scores very low', () {
      final mat = flatMat();
      final score = detector.sharpnessScore(mat);
      expect(score, lessThan(10));
      mat.dispose();
    });

    test('a high-frequency checkerboard scores far higher than a flat image', () {
      final flat = flatMat();
      final sharp = checkerboardMat(cell: 6);

      final flatScore = detector.sharpnessScore(flat);
      final sharpScore = detector.sharpnessScore(sharp);

      expect(sharpScore, greaterThan(flatScore));
      disposeAll([flat, sharp]);
    });

    test('isSharpEnough is true above kMinSharpnessScore, false below it', () {
      final flat = flatMat();
      final sharp = checkerboardMat(cell: 4);

      expect(detector.isSharpEnough(flat), isFalse);
      expect(detector.isSharpEnough(sharp), isTrue);
      disposeAll([flat, sharp]);
    });

    test('works on an already-grayscale (single channel) Mat without converting again', () {
      final colorSharp = checkerboardMat(cell: 6);
      final graySharp = cv.cvtColor(colorSharp, cv.COLOR_BGR2GRAY);
      expect(() => detector.sharpnessScore(graySharp), returnsNormally);
      disposeAll([colorSharp, graySharp]);
    });

    test('sharpness score is non-negative (it is a squared std-dev)', () {
      final mat = checkerboardMat();
      expect(detector.sharpnessScore(mat), greaterThanOrEqualTo(0));
      mat.dispose();
    });
  });
}
