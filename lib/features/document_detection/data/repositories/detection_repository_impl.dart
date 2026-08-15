import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../domain/entities/detected_document.dart';
import '../../domain/repositories/detection_repository.dart';
import '../datasources/document_detection_datasource.dart';

class DetectionRepositoryImpl implements DetectionRepository {
  final DocumentDetectionDataSource dataSource;

  DetectionRepositoryImpl(this.dataSource);

  @override
  DetectedDocument detectDocument(cv.Mat frame) => dataSource.detectCard(frame);

  @override
  cv.Mat warpDocument(cv.Mat frame, CardQuad quad) => dataSource.warpCard(frame, quad);

  @override
  void resetTracking() => dataSource.resetTracking();

  @override
  (PhotoDetectionResult, CardRect?) detectPhoto(cv.Mat warpedCard) =>
      dataSource.detectPhotoWithOrientation(warpedCard);

  @override
  cv.Mat loadTemplateFromBytes(Uint8List bytes) => dataSource.loadTemplateFromBytes(bytes);

  @override
  (bool, double) detectLogo(cv.Mat orientedCard, cv.Mat templateLogo) =>
      dataSource.detectLogo(orientedCard, templateLogo);

  @override
  (bool, double) detectFlag(cv.Mat orientedCard, cv.Mat templateFlag) =>
      dataSource.detectFlag(orientedCard, templateFlag);

  @override
  cv.Mat applyRotation(cv.Mat image, int degrees) =>
      dataSource.applyRotation(image, degrees);

  @override
  (bool, double) detectBarcodePresence(cv.Mat orientedCard) =>
      dataSource.detectBarcodePresence(orientedCard);

  @override
  (bool, double) detectFingerprintPresence(cv.Mat orientedCard) =>
      dataSource.detectFingerprintPresence(orientedCard);

  @override
  (bool, (int, int, int, int)?, double) detectSeparationLine(cv.Mat orientedCard) =>
      dataSource.detectSeparationLine(orientedCard);

  @override
  BackOrientationResult detectBackOrientation(cv.Mat warpedCard) =>
      dataSource.detectBackOrientation(warpedCard);

  // ASSUMPTION (unverified against the installed opencv_dart version):
  // `cv.imencode` returns a `(bool success, Uint8List bytes)` tuple, mirroring
  // `cv.imdecode` already used in template_matcher.dart. If `flutter analyze`
  // flags this call, check the actual signature in
  // `.dart_tool/.../opencv_dart/lib/src/imgcodecs/imgcodecs.dart` and adjust -
  // it may return just `Uint8List`, or take a `params` argument.
  @override
  Uint8List encodeToPng(cv.Mat image) {
    final (success, bytes) = cv.imencode('.png', image);
    if (!success) {
      throw StateError('Échec de l\'encodage PNG de la carte capturée.');
    }
    return bytes;
  }

  @override
  cv.Mat decodePng(Uint8List pngBytes) => cv.imdecode(pngBytes, cv.IMREAD_COLOR);
}