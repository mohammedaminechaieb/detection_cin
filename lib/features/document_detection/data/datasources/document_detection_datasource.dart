import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../domain/entities/detected_document.dart';
import 'detectors/back_orientation_detector.dart';
import 'detectors/barcode_area_detector.dart';
import 'detectors/card_rotator.dart';
import 'detectors/document_contour_detector.dart';
import 'detectors/face_orientation_detector.dart';
import 'detectors/fingerprint_presence_detector.dart';
import 'detectors/perspective_warper.dart';
import 'detectors/separation_line_detector.dart';
import 'detectors/template_matcher.dart';

/// Composes the individual card-detection algorithms (contour/tracking,
/// perspective warp, face/orientation, template matching, barcode,
/// fingerprint, separation line) behind the single interface
/// [DetectionRepository] depends on.
///
/// Each algorithm lives in its own class under `detectors/` - this facade
/// only wires them together and forwards calls, so it stays a thin
/// composition root rather than a god class.
class DocumentDetectionDataSource {
  DocumentDetectionDataSource(String cascadePath)
      : _contourDetector = DocumentContourDetector(),
        _warper = PerspectiveWarper(),
        _faceDetector = FaceOrientationDetector(cascadePath),
        _templateMatcher = const TemplateMatcher(),
        _barcodeDetector = BarcodeAreaDetector(),
        _fingerprintDetector = const FingerprintPresenceDetector(),
        _separationLineDetector = const SeparationLineDetector(),
        _rotator = const CardRotator() {
    _backOrientationDetector = BackOrientationDetector(
      _barcodeDetector,
      _fingerprintDetector,
      _separationLineDetector,
      rotator: _rotator,
    );
  }

  final DocumentContourDetector _contourDetector;
  final PerspectiveWarper _warper;
  final FaceOrientationDetector _faceDetector;
  final TemplateMatcher _templateMatcher;
  final BarcodeAreaDetector _barcodeDetector;
  final FingerprintPresenceDetector _fingerprintDetector;
  final SeparationLineDetector _separationLineDetector;
  final CardRotator _rotator;
  late final BackOrientationDetector _backOrientationDetector;

  void resetTracking() => _contourDetector.resetTracking();

  DetectedDocument detectCard(cv.Mat image) => _contourDetector.detectCard(image);

  cv.Mat warpCard(cv.Mat image, CardQuad quad) => _warper.warp(image, quad);

  (PhotoDetectionResult, CardRect?) detectPhotoWithOrientation(cv.Mat warpedCard) =>
      _faceDetector.detect(warpedCard);

  cv.Mat applyRotation(cv.Mat image, int degrees) => _rotator.apply(image, degrees);

  cv.Mat loadTemplateFromBytes(Uint8List bytes) => _templateMatcher.loadTemplateFromBytes(bytes);

  cv.Mat loadTemplate(String path) => _templateMatcher.loadTemplateFromFile(path);

  (bool, double) detectLogo(cv.Mat orientedCard, cv.Mat templateLogo) =>
      _templateMatcher.detectLogo(orientedCard, templateLogo);

  (bool, double) detectFlag(cv.Mat orientedCard, cv.Mat templateFlag) =>
      _templateMatcher.detectFlag(orientedCard, templateFlag);

  (bool, double) detectBarcodePresence(cv.Mat orientedCard) =>
      _barcodeDetector.detect(orientedCard);

  void disposeBarcodeDetector() => _barcodeDetector.dispose();

  (bool, double) detectFingerprintPresence(cv.Mat orientedCard) =>
      _fingerprintDetector.detect(orientedCard);

  (bool, (int, int, int, int)?, double) detectSeparationLine(cv.Mat orientedCard) =>
      _separationLineDetector.detect(orientedCard);

  /// Finds the back-side card's correct rotation and returns the
  /// barcode/fingerprint/separation-line results already computed at
  /// that rotation - see [BackOrientationDetector] for why this needs to
  /// exist at all (there's no face to orient the back by like the front
  /// has). Takes the raw `warped` card, not an oriented one - orienting
  /// it correctly is exactly what this determines.
  BackOrientationResult detectBackOrientation(cv.Mat warpedCard) =>
      _backOrientationDetector.detect(warpedCard);
}
