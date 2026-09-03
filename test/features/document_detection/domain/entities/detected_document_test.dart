// Tier A - pure Dart entities, no mocks, no platform. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/document_detection/domain/entities/detected_document.dart';

void main() {
  group('CardQuad', () {
    test('toOffsets preserves corner order (TL, TR, BR, BL)', () {
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(10, 0),
        bottomRight: CardPoint(10, 10),
        bottomLeft: CardPoint(0, 10),
      );
      final offsets = quad.toOffsets();
      expect(offsets, [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 10),
        const Offset(0, 10),
      ]);
    });
  });

  group('DetectedDocument.none()', () {
    test('produces a not-detected, quad-less, zero-score result', () {
      final none = DetectedDocument.none();
      expect(none.isDetected, isFalse);
      expect(none.quad, isNull);
      expect(none.score, 0);
      expect(none.source, '');
    });
  });

  group('PhotoDetectionResult.none()', () {
    test('produces a not-found, zero-rotation, zero-confidence result', () {
      final none = PhotoDetectionResult.none();
      expect(none.found, isFalse);
      expect(none.rotationDegrees, 0);
      expect(none.confidence, 0);
    });
  });

  group('BackOrientationResult.none()', () {
    test('produces an all-false/zero result', () {
      final none = BackOrientationResult.none();
      expect(none.rotationDegrees, 0);
      expect(none.barcodeFound, isFalse);
      expect(none.barcodeScore, 0);
      expect(none.fingerprintFound, isFalse);
      expect(none.fingerprintScore, 0);
      expect(none.separationLineFound, isFalse);
      expect(none.separationLineBox, isNull);
      expect(none.separationLineScore, 0);
    });
  });

  group('CardAnalysisResult.none()', () {
    test('bundles DetectedDocument.none() and PhotoDetectionResult.none()', () {
      final none = CardAnalysisResult.none();
      expect(none.document.isDetected, isFalse);
      expect(none.photo.found, isFalse);
      expect(none.faceBox, isNull);
      expect(none.logoFound, isFalse);
      expect(none.logoScore, 0);
      expect(none.flagFound, isFalse);
      expect(none.flagScore, 0);
    });
  });

  group('BackAnalysisResult.none()', () {
    test('bundles DetectedDocument.none() with all-false back-side signals', () {
      final none = BackAnalysisResult.none();
      expect(none.document.isDetected, isFalse);
      expect(none.rotationDegrees, 0);
      expect(none.barcodeFound, isFalse);
      expect(none.fingerprintFound, isFalse);
      expect(none.separationLineFound, isFalse);
    });
  });

  group('CardSide', () {
    test('has exactly front and back', () {
      expect(CardSide.values, [CardSide.front, CardSide.back]);
    });
  });
}
