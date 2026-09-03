// Tier B - mocks DocumentDetectionDataSource (mocktail); verifies the
// repository is a thin, correct pass-through, without exercising real
// OpenCV detection. See test/README.md. Still needs opencv_dart to
// compile (cv.Mat/Uint8List types), but never calls into native code.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:detection_cin/features/document_detection/data/datasources/document_detection_datasource.dart';
import 'package:detection_cin/features/document_detection/data/repositories/detection_repository_impl.dart';
import 'package:detection_cin/features/document_detection/domain/entities/detected_document.dart';

class MockDataSource extends Mock implements DocumentDetectionDataSource {}

class FakeMat extends Fake implements cv.Mat {}

class FakeCardQuad extends Fake implements CardQuad {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeMat());
    registerFallbackValue(FakeCardQuad());
  });

  late MockDataSource dataSource;
  late DetectionRepositoryImpl repository;

  setUp(() {
    dataSource = MockDataSource();
    repository = DetectionRepositoryImpl(dataSource);
  });

  test('detectDocument delegates to dataSource.detectCard', () {
    final frame = FakeMat();
    final expected = DetectedDocument.none();
    when(() => dataSource.detectCard(frame)).thenReturn(expected);

    expect(repository.detectDocument(frame), same(expected));
    verify(() => dataSource.detectCard(frame)).called(1);
  });

  test('warpDocument delegates to dataSource.warpCard', () {
    final frame = FakeMat();
    final quad = FakeCardQuad();
    final warped = FakeMat();
    when(() => dataSource.warpCard(frame, quad)).thenReturn(warped);

    expect(repository.warpDocument(frame, quad), same(warped));
  });

  test('resetTracking delegates to dataSource.resetTracking', () {
    repository.resetTracking();
    verify(() => dataSource.resetTracking()).called(1);
  });

  test('detectPhoto delegates to dataSource.detectPhotoWithOrientation', () {
    final warped = FakeMat();
    final expected = (PhotoDetectionResult.none(), null);
    when(() => dataSource.detectPhotoWithOrientation(warped)).thenReturn(expected);

    expect(repository.detectPhoto(warped), expected);
  });

  test('detectBackOrientation delegates to dataSource.detectBackOrientation', () {
    final warped = FakeMat();
    final expected = BackOrientationResult.none();
    when(() => dataSource.detectBackOrientation(warped)).thenReturn(expected);

    expect(repository.detectBackOrientation(warped), same(expected));
  });

  test('detectLogo / detectFlag delegate with both arguments forwarded unchanged', () {
    final card = FakeMat();
    final template = FakeMat();
    when(() => dataSource.detectLogo(card, template)).thenReturn((true, 0.9));
    when(() => dataSource.detectFlag(card, template)).thenReturn((false, 0.1));

    expect(repository.detectLogo(card, template), (true, 0.9));
    expect(repository.detectFlag(card, template), (false, 0.1));
  });

  test('detectBarcodePresence / detectFingerprintPresence / detectSeparationLine delegate', () {
    final card = FakeMat();
    when(() => dataSource.detectBarcodePresence(card)).thenReturn((true, 0.5, true));
    when(() => dataSource.detectFingerprintPresence(card)).thenReturn((true, 300.0));
    when(() => dataSource.detectSeparationLine(card)).thenReturn((true, (0, 0, 10, 10), 0.7));

    expect(repository.detectBarcodePresence(card), (true, 0.5, true));
    expect(repository.detectFingerprintPresence(card), (true, 300.0));
    expect(repository.detectSeparationLine(card), (true, (0, 0, 10, 10), 0.7));
  });

  test('applyRotation delegates with the same degrees value', () {
    final image = FakeMat();
    final rotated = FakeMat();
    when(() => dataSource.applyRotation(image, 90)).thenReturn(rotated);

    expect(repository.applyRotation(image, 90), same(rotated));
  });

  test('loadTemplateFromBytes delegates to dataSource.loadTemplateFromBytes', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final template = FakeMat();
    when(() => dataSource.loadTemplateFromBytes(bytes)).thenReturn(template);

    expect(repository.loadTemplateFromBytes(bytes), same(template));
  });

  // NOTE: encodeToPng/decodePng call cv.imencode/cv.imdecode directly
  // (they do NOT go through DocumentDetectionDataSource), so they're not
  // exercisable via this mock and aren't covered here - see the Tier C/D
  // notes in integration_test/ for real-Mat coverage of those two.
}
