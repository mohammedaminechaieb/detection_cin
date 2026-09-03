// Tier C - needs opencv_dart's native binary, no device required, uses
// synthetic in-memory Mats standing in for the fingerprint ROI.
// See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/document_detection/data/datasources/detectors/fingerprint_presence_detector.dart';

import '../../../../../test_helpers/mat_test_utils.dart';

void main() {
  const detector = FingerprintPresenceDetector();

  group('FingerprintPresenceDetector.detect', () {
    test('a blank/flat card (no texture anywhere) is not found (variance below minVariance)', () {
      final card = flatMat(width: 856, height: 540, gray: 200);
      final (found, variance) = detector.detect(card);
      expect(found, isFalse);
      expect(variance, lessThan(150));
      card.dispose();
    });

    test('a moderately textured ROI (checkerboard) with the fingerprint-scale cell size is found', () {
      final card = checkerboardMat(width: 856, height: 540, cell: 14, darkValue: 120, lightValue: 180);
      final (found, _) = detector.detect(card);
      expect(found, isTrue);
      card.dispose();
    });

    test('an extremely noisy/high-contrast ROI (well above maxVariance) is not found', () {
      // Very fine, very high-contrast checkerboard - well beyond what real
      // fingerprint ridge texture looks like, simulating glare/smudge noise.
      final card = checkerboardMat(width: 856, height: 540, cell: 1, darkValue: 0, lightValue: 255);
      final (found, variance) = detector.detect(card);
      expect(found, isFalse);
      expect(variance, greaterThan(4000));
      card.dispose();
    });

    test('custom minVariance/maxVariance bounds are honored', () {
      final card = checkerboardMat(width: 856, height: 540, cell: 14, darkValue: 120, lightValue: 180);
      final (foundDefault, variance) = detector.detect(card);
      expect(foundDefault, isTrue);

      final (foundNarrow, _) = detector.detect(card, minVariance: variance + 100, maxVariance: variance + 200);
      expect(foundNarrow, isFalse, reason: 'raising minVariance above the measured value should reject it');
      card.dispose();
    });
  });
}
