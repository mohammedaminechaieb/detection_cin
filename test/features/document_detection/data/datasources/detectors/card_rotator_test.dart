// Tier C - needs opencv_dart's native binary, no device required, uses
// synthetic in-memory Mats (test_helpers/mat_test_utils.dart).
// See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:detection_cin/features/document_detection/data/datasources/detectors/card_rotator.dart';

import '../../../../../test_helpers/mat_test_utils.dart';

void main() {
  const rotator = CardRotator();

  group('CardRotator.apply', () {
    test('degrees: 0 returns the identical instance (no rotation, no copy)', () {
      final mat = flatMat(width: 80, height: 40);
      final result = rotator.apply(mat, 0);
      expect(identical(result, mat), isTrue);
      mat.dispose();
    });

    test('degrees: 90 swaps width and height', () {
      final mat = checkerboardMat(width: 80, height: 40);
      final rotated = rotator.apply(mat, 90);
      expect(identical(rotated, mat), isFalse);
      expect(rotated.cols, 40);
      expect(rotated.rows, 80);
      disposeAll([mat, rotated]);
    });

    test('degrees: 270 swaps width and height (opposite rotation direction from 90)', () {
      final mat = checkerboardMat(width: 80, height: 40);
      final rotated = rotator.apply(mat, 270);
      expect(rotated.cols, 40);
      expect(rotated.rows, 80);
      disposeAll([mat, rotated]);
    });

    test('degrees: 180 preserves width and height', () {
      final mat = checkerboardMat(width: 80, height: 40);
      final rotated = rotator.apply(mat, 180);
      expect(rotated.cols, 80);
      expect(rotated.rows, 40);
      disposeAll([mat, rotated]);
    });

    test('rotating 90 then 90 again (180 total) matches a direct 180 rotation, pixel-for-pixel', () {
      final mat = checkerboardMat(width: 80, height: 40, cell: 5);
      final twice90 = rotator.apply(rotator.apply(mat, 90), 90);
      final direct180 = rotator.apply(mat, 180);

      final diff = cv.absDiff(twice90, direct180);
      final diffGray = cv.cvtColor(diff, cv.COLOR_BGR2GRAY);
      final nonZeroPixels = cv.countNonZero(diffGray);
      expect(nonZeroPixels, 0);

      disposeAll([mat, twice90, direct180, diff, diffGray]);
    });

    test('an unrecognized degree value (e.g. 45) falls through to no rotation (identical instance)', () {
      final mat = flatMat();
      final result = rotator.apply(mat, 45);
      expect(identical(result, mat), isTrue);
      mat.dispose();
    });
  });
}
