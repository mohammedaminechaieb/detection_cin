import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../../shared/utils/camera_image_converter.dart';
import '../../../../shared/utils/detection_stabilizer.dart';
import '../../domain/entities/detected_document.dart';
import '../../domain/repositories/detection_repository.dart';

/// Drives the live camera analysis loop: converts each camera frame to a
/// Mat, runs it through [DetectionRepository], and exposes stabilized
/// detection state for the UI to render.
class DetectionViewModel extends ChangeNotifier {
  DetectionViewModel(
    this.repository, {
    CameraImageConverter? imageConverter,
    DetectionStabilizer? stabilizer,
  })  : _imageConverter = imageConverter ?? const CameraImageConverter(),
        _stabilizer = stabilizer ?? DetectionStabilizer();

  final DetectionRepository repository;
  final CameraImageConverter _imageConverter;
  final DetectionStabilizer _stabilizer;

  cv.Mat? _logoTemplate;
  cv.Mat? _flagTemplate;

  void loadTemplates({required Uint8List logoBytes, required Uint8List flagBytes}) {
    _logoTemplate = repository.loadTemplateFromBytes(logoBytes);
    _flagTemplate = repository.loadTemplateFromBytes(flagBytes);
  }

  CardSide _currentSide = CardSide.front;
  CardSide get currentSide => _currentSide;

  void setSide(CardSide side) {
    _currentSide = side;
    _stabilizer.resetAll();
    repository.resetTracking();
    notifyListeners();
  }

  CardAnalysisResult _lastFrontResult = CardAnalysisResult.none();
  BackAnalysisResult _lastBackResult = BackAnalysisResult.none();
  CardAnalysisResult get lastFrontResult => _lastFrontResult;
  BackAnalysisResult get lastBackResult => _lastBackResult;

  bool get isBorderDetected => _stabilizer.isStable('border');
  bool get isFaceDetected => _stabilizer.isStable('face');
  bool get isLogoDetected => _stabilizer.isStable('logo');
  bool get isFlagDetected => _stabilizer.isStable('flag');

  bool get isBarcodeDetected => _stabilizer.isStable('barcode');
  bool get isFingerprintDetected => _stabilizer.isStable('fingerprint');
  bool get isSeparationLineDetected => _stabilizer.isStable('separation_line');

  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  static const _throttle = Duration(milliseconds: 350);
  bool _busy = false;

  /// Receives the Mat converted from each analyzed frame, for debug
  /// preview overlays. The Mat is disposed as soon as [onFrame] finishes,
  /// so implementations must use it synchronously and not retain it.
  void Function(cv.Mat mat)? onDebugFrame;

  void onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_busy || now.difference(_lastAnalysis) < _throttle) return;

    _busy = true;
    _lastAnalysis = now;

    cv.Mat? mat;
    cv.Mat? warped;
    try {
      mat = _imageConverter.toBgrMat(image);
      onDebugFrame?.call(mat);

      final document = repository.detectDocument(mat);

      if (!document.isDetected || document.quad == null) {
        _stabilizer.resetAll();
        if (_currentSide == CardSide.front) {
          _lastFrontResult = CardAnalysisResult.none();
        } else {
          _lastBackResult = BackAnalysisResult.none();
        }
        notifyListeners();
        return;
      }

      warped = repository.warpDocument(mat, document.quad!);

      if (_currentSide == CardSide.front) {
        _analyzeFront(document, warped);
      } else {
        _analyzeBack(document, warped);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Erreur detection frame: $e');
    } finally {
      // `warped` and `mat` are distinct Mats (warpDocument always allocates
      // a new one), so disposing both here is always safe.
      warped?.dispose();
      mat?.dispose();
      _busy = false;
    }
  }

  void _analyzeFront(DetectedDocument document, cv.Mat warped) {
    final (photo, faceBox) = repository.detectPhoto(warped);
    final oriented = repository.applyRotation(warped, photo.rotationDegrees);

    var logoFound = false;
    var logoScore = 0.0;
    var flagFound = false;
    var flagScore = 0.0;

    if (_logoTemplate != null) {
      final (found, score) = repository.detectLogo(oriented, _logoTemplate!);
      logoFound = found;
      logoScore = score;
    }
    if (_flagTemplate != null) {
      final (found, score) = repository.detectFlag(oriented, _flagTemplate!);
      flagFound = found;
      flagScore = score;
    }

    // applyRotation returns the same Mat instance (not a copy) when no
    // rotation is needed, so only dispose `oriented` when it's a distinct
    // Mat - otherwise this would double-free `warped`, which the caller
    // (onFrame) also disposes.
    if (!identical(oriented, warped)) {
      oriented.dispose();
    }

    _lastFrontResult = CardAnalysisResult(
      document: document,
      photo: photo,
      faceBox: faceBox,
      logoFound: logoFound,
      logoScore: logoScore,
      flagFound: flagFound,
      flagScore: flagScore,
    );

    _stabilizer.update('border', document.isDetected);
    _stabilizer.update('face', photo.found);
    _stabilizer.update('logo', logoFound);
    _stabilizer.update('flag', flagFound);
  }

  void _analyzeBack(DetectedDocument document, cv.Mat warped) {
    final (barcodeFound, barcodeScore) = repository.detectBarcodePresence(warped);
    final (fingerprintFound, fingerprintScore) = repository.detectFingerprintPresence(warped);
    final (lineFound, _, lineScore) = repository.detectSeparationLine(warped);

    _lastBackResult = BackAnalysisResult(
      document: document,
      barcodeFound: barcodeFound,
      barcodeScore: barcodeScore,
      fingerprintFound: fingerprintFound,
      fingerprintScore: fingerprintScore,
      separationLineFound: lineFound,
      separationLineScore: lineScore,
    );

    _stabilizer.update('border', document.isDetected);
    _stabilizer.update('barcode', barcodeFound);
    _stabilizer.update('fingerprint', fingerprintFound);
    _stabilizer.update('separation_line', lineFound, framesToConfirm: 1);
  }
}
