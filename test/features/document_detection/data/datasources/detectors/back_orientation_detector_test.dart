// Tier B - mocks BarcodeAreaDetector, FingerprintPresenceDetector,
// SeparationLineDetector, and CardRotator (all concrete, non-final
// classes, mockable directly via mocktail). Verifies the scoring/
// rotation-selection logic without running real OpenCV detection.
// See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:detection_cin/features/document_detection/data/datasources/detectors/back_orientation_detector.dart';
import 'package:detection_cin/features/document_detection/data/datasources/detectors/barcode_area_detector.dart';
import 'package:detection_cin/features/document_detection/data/datasources/detectors/card_rotator.dart';
import 'package:detection_cin/features/document_detection/data/datasources/detectors/fingerprint_presence_detector.dart';
import 'package:detection_cin/features/document_detection/data/datasources/detectors/separation_line_detector.dart';
import 'package:detection_cin/features/document_detection/domain/entities/detected_document.dart';

class MockBarcodeAreaDetector extends Mock implements BarcodeAreaDetector {}

class MockFingerprintPresenceDetector extends Mock implements FingerprintPresenceDetector {}

class MockSeparationLineDetector extends Mock implements SeparationLineDetector {}

class MockCardRotator extends Mock implements CardRotator {}

class FakeMat extends Fake implements cv.Mat {
  // BackOrientationDetector disposes each rotated candidate Mat that
  // isn't the original warpedCard instance. `Fake`'s default
  // noSuchMethod throws UnimplementedError for any unstubbed call, so
  // dispose() needs a real (no-op) override rather than being left to
  // fall through to that default.
  @override
  void dispose() {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeMat());
  });

  late MockBarcodeAreaDetector barcode;
  late MockFingerprintPresenceDetector fingerprint;
  late MockSeparationLineDetector separationLine;
  late MockCardRotator rotator;
  late FakeMat warpedCard;

  setUp(() {
    barcode = MockBarcodeAreaDetector();
    fingerprint = MockFingerprintPresenceDetector();
    separationLine = MockSeparationLineDetector();
    rotator = MockCardRotator();
    warpedCard = FakeMat();

    // rotator.apply returns a distinct fake Mat per angle by default so
    // the detector's "dispose if not identical to warpedCard" branch is
    // exercised without a double-free (Fake Mats have no real dispose
    // cost).
    when(() => rotator.apply(warpedCard, any())).thenAnswer((_) => FakeMat());
  });

  BackOrientationResult run() => BackOrientationDetector(barcode, fingerprint, separationLine, rotator: rotator)
      .detect(warpedCard);

  test('picks the rotation where all three signals agree, applying the +180 correction', () {
    // Make every candidate score 0 except the one at rotator angle 90,
    // which scores maximally (barcode found+in-position, fingerprint
    // found, line found).
    when(() => barcode.detect(any())).thenReturn((false, 0.0, false));
    when(() => fingerprint.detect(any())).thenReturn((false, 0.0));
    when(() => separationLine.detect(any())).thenReturn((false, null, 0.0));

    cv.Mat? bestRotated;
    when(() => rotator.apply(warpedCard, 90)).thenAnswer((_) {
      bestRotated = FakeMat();
      return bestRotated!;
    });
    when(() => barcode.detect(any(that: predicate((m) => identical(m, bestRotated)))))
        .thenReturn((true, 0.5, true));
    when(() => fingerprint.detect(any(that: predicate((m) => identical(m, bestRotated)))))
        .thenReturn((true, 300.0));
    when(() => separationLine.detect(any(that: predicate((m) => identical(m, bestRotated)))))
        .thenReturn((true, (0, 0, 10, 10), 0.8));

    final result = run();

    expect(result.rotationDegrees, (90 + 180) % 360);
    expect(result.barcodeFound, isTrue);
    expect(result.fingerprintFound, isTrue);
    expect(result.separationLineFound, isTrue);
  });

  test('when no candidate finds anything, falls back to angle 0 (+180 correction) with all-false result', () {
    when(() => barcode.detect(any())).thenReturn((false, 0.0, false));
    when(() => fingerprint.detect(any())).thenReturn((false, 0.0));
    when(() => separationLine.detect(any())).thenReturn((false, null, 0.0));

    final result = run();

    expect(result.rotationDegrees, 180); // (0 + 180) % 360, first candidate wins ties
    expect(result.barcodeFound, isFalse);
    expect(result.fingerprintFound, isFalse);
    expect(result.separationLineFound, isFalse);
  });

  test('barcode found but NOT in expected position contributes 0 to the score (does not count as a full vote)', () {
    // barcodeInPosition=false should score the same as barcode not found
    // at all for selection purposes.
    when(() => barcode.detect(any())).thenReturn((true, 0.9, false));
    when(() => fingerprint.detect(any())).thenReturn((false, 0.0));
    when(() => separationLine.detect(any())).thenReturn((false, null, 0.0));

    final result = run();
    // barcodeFound is still reported true (it's a distinct field from the
    // score contribution), but no candidate should "win" more than any
    // other purely because of this - the first one (angle 0) wins ties.
    expect(result.rotationDegrees, 180);
  });

  test('all four candidate rotations are tried exactly once', () {
    when(() => barcode.detect(any())).thenReturn((false, 0.0, false));
    when(() => fingerprint.detect(any())).thenReturn((false, 0.0));
    when(() => separationLine.detect(any())).thenReturn((false, null, 0.0));

    run();

    verify(() => rotator.apply(warpedCard, 0)).called(1);
    verify(() => rotator.apply(warpedCard, 90)).called(1);
    verify(() => rotator.apply(warpedCard, 180)).called(1);
    verify(() => rotator.apply(warpedCard, 270)).called(1);
  });
}
