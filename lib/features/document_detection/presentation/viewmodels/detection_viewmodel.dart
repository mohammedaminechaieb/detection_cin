import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../../shared/utils/camera_image_converter.dart';
import '../../../../shared/utils/detection_stabilizer.dart';
import '../../../image_quality/data/datasources/detectors/blur_detector.dart';
import '../../../image_quality/data/datasources/detectors/brightness_detector.dart';
import '../../../image_quality/data/datasources/detectors/stability_tracker.dart';
import '../../domain/entities/detected_document.dart';
import '../../domain/usecases/detect_back_orientation.dart';
import '../../../autocapture/domain/entities/capture_state.dart';
import '../../../autocapture/domain/entities/quality_report.dart';
import '../../domain/repositories/detection_repository.dart';
import '../../../autocapture/presentation/viewmodels/autocapture_viewmodel.dart';

/// Drives the live camera analysis loop: converts each camera frame to a
/// Mat, runs it through [DetectionRepository], and exposes stabilized
/// detection state for the UI to render.
///
/// Since Step 3, it also runs the quality checks (sharpness, brightness,
/// quad stability) each frame and forwards a [QualityReport] to
/// [autocaptureViewModel], if one was provided.
class DetectionViewModel extends ChangeNotifier {
  DetectionViewModel(
    this.repository, {
    CameraImageConverter? imageConverter,
    DetectionStabilizer? stabilizer,
    BlurDetector? blurDetector,
    BrightnessDetector? brightnessDetector,
    StabilityTracker? stabilityTracker,
    DetectBackOrientation? detectBackOrientation,
    this.autocaptureViewModel,
  })  : _imageConverter = imageConverter ?? const CameraImageConverter(),
        _stabilizer = stabilizer ?? DetectionStabilizer(),
        _blurDetector = blurDetector ?? const BlurDetector(),
        _brightnessDetector = brightnessDetector ?? const BrightnessDetector(),
        _stabilityTracker = stabilityTracker ?? StabilityTracker(),
        _detectBackOrientation = detectBackOrientation ?? DetectBackOrientation(repository);

  final DetectionRepository repository;
  final CameraImageConverter _imageConverter;
  final DetectionStabilizer _stabilizer;
  final BlurDetector _blurDetector;
  final BrightnessDetector _brightnessDetector;
  final StabilityTracker _stabilityTracker;
  final DetectBackOrientation _detectBackOrientation;

  /// Optional - if provided, [onFrame] feeds it a [QualityReport] every
  /// analyzed frame so it can drive the Step 3 autocapture state machine.
  final AutocaptureViewModel? autocaptureViewModel;

  /// Fired exactly once per capture cycle, the frame [autocaptureViewModel]
  /// transitions into [CaptureState.captured] - carries the PNG-encoded
  /// warped card for that side. `null` if no [autocaptureViewModel] was
  /// provided (nothing will ever fire).
  void Function(Uint8List pngBytes, CardSide side)? onCardCaptured;

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
    _stabilityTracker.reset();
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
        _stabilityTracker.reset();
        autocaptureViewModel?.onFrame(const QualityReport(
          quadFound: false,
          sharpnessScore: 0,
          brightness: BrightnessStatus.ok,
          isStable: false,
          contentMatched: false,
        ));
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

      final contentMatched = _currentSide == CardSide.front
          ? (_lastFrontResult.logoFound && _lastFrontResult.flagFound)
          : (_lastBackResult.barcodeFound &&
              _lastBackResult.fingerprintFound &&
              _lastBackResult.separationLineFound);

      _stabilityTracker.update(document.quad!.toOffsets());
      final report = QualityReport(
        quadFound: true,
        sharpnessScore: _blurDetector.sharpnessScore(warped),
        brightness: _brightnessDetector.classify(warped),
        isStable: _stabilityTracker.isStable,
        contentMatched: contentMatched,
      );

      final wasCaptured = autocaptureViewModel?.state == CaptureState.captured;
      autocaptureViewModel?.onFrame(report);
      final justCaptured = !wasCaptured && autocaptureViewModel?.state == CaptureState.captured;
      if (justCaptured) {
        // The saved image must be upright, not just cropped - `warped` is
        // only perspective-corrected, not rotation-corrected. Front already
        // knows its rotation cheaply (from face detection, done above in
        // `_analyzeFront`); back has no face to anchor on, so this runs the
        // one-time 4-rotation search instead (see `DetectBackOrientation` -
        // deliberately NOT run every frame, only here at capture time).
        final rotationDegrees = _currentSide == CardSide.front
            ? _lastFrontResult.photo.rotationDegrees
            : _detectBackOrientation(warped).$1;
        final finalImage = repository.applyRotation(warped, rotationDegrees);
        onCardCaptured?.call(repository.encodeToPng(finalImage), _currentSide);
        if (!identical(finalImage, warped)) {
          finalImage.dispose();
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Erreur detection frame: $e');
    } finally {
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