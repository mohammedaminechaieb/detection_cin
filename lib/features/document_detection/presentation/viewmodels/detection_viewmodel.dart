import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../domain/entities/detected_document.dart';
import '../../domain/repositories/detection_repository.dart';

class DetectionViewModel extends ChangeNotifier {
  final DetectionRepository repository;

  DetectionViewModel(this.repository);

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
    _resetAllStreaks();
    repository.resetTracking();
    notifyListeners();
  }

  CardAnalysisResult _lastFrontResult = CardAnalysisResult.none();
  BackAnalysisResult _lastBackResult = BackAnalysisResult.none();
  CardAnalysisResult get lastFrontResult => _lastFrontResult;
  BackAnalysisResult get lastBackResult => _lastBackResult;

  
  static const int _framesToConfirm = 3;
  static const int _framesToReset = 2;

  final Map<String, int> _hitStreaks = {};
  final Map<String, int> _missStreaks = {};
  final Map<String, bool> _stableStates = {};

  bool _stable(String key) => _stableStates[key] ?? false;

  void _updateOne(String key, bool raw, {int framesToConfirm = _framesToConfirm}) {
    final hit = _hitStreaks[key] ?? 0;
    final miss = _missStreaks[key] ?? 0;

    if (raw) {
      _hitStreaks[key] = hit + 1;
      _missStreaks[key] = 0;
      if (_hitStreaks[key]! >= _framesToConfirm) _stableStates[key] = true;
    } else {
      _missStreaks[key] = miss + 1;
      _hitStreaks[key] = 0;
      if (_missStreaks[key]! >= _framesToReset) _stableStates[key] = false;
    }
  }

  void _resetAllStreaks() {
    _hitStreaks.clear();
    _missStreaks.clear();
    _stableStates.clear();
  }

  
  bool get isBorderDetected => _stable('border');
  bool get isFaceDetected => _stable('face');
  bool get isLogoDetected => _stable('logo');
  bool get isFlagDetected => _stable('flag');

  
  bool get isBarcodeDetected => _stable('barcode');
  bool get isFingerprintDetected => _stable('fingerprint');
  bool get isSeparationLineDetected => _stable('separation_line');

  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  static const _throttle = Duration(milliseconds: 350);
  bool _busy = false;

  void Function(cv.Mat mat)? onDebugFrame;

  void onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_busy || now.difference(_lastAnalysis) < _throttle) return;

    _busy = true;
    _lastAnalysis = now;

    try {
      final mat = _cameraImageToMat(image);
      onDebugFrame?.call(mat);

      final document = repository.detectDocument(mat);

      if (!document.isDetected || document.quad == null) {
        _resetAllStreaks();
        if (_currentSide == CardSide.front) {
          _lastFrontResult = CardAnalysisResult.none();
        } else {
          _lastBackResult = BackAnalysisResult.none();
        }
        notifyListeners();
        return;
      }

      final warped = repository.warpDocument(mat, document.quad!);

      if (_currentSide == CardSide.front) {
        _analyzeFront(document, warped);
      } else {
        _analyzeBack(document, warped);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Erreur detection frame: $e');
    } finally {
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

    _lastFrontResult = CardAnalysisResult(
      document: document,
      photo: photo,
      faceBox: faceBox,
      logoFound: logoFound,
      logoScore: logoScore,
      flagFound: flagFound,
      flagScore: flagScore,
    );

    _updateOne('border', document.isDetected);
    _updateOne('face', photo.found);
    _updateOne('logo', logoFound);
    _updateOne('flag', flagFound);
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

    _updateOne('border', document.isDetected);
    _updateOne('barcode', barcodeFound);
    _updateOne('fingerprint', fingerprintFound);
    _updateOne('separation_line', lineFound, framesToConfirm: 1);
  }

  cv.Mat _cameraImageToMat(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      final mat = cv.Mat.fromList(
        image.height,
        image.width,
        cv.MatType.CV_8UC4,
        plane.bytes,
      );
      return cv.cvtColor(mat, cv.COLOR_BGRA2BGR);
    }
    return _convertYuv420ToMat(image);
  }

  cv.Mat _convertYuv420ToMat(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height + 2 * (width ~/ 2) * (height ~/ 2));

    var offset = 0;
    final yRowStride = yPlane.bytesPerRow.toInt();
    for (var row = 0; row < height; row++) {
      final rowStart = row * yRowStride;
      nv21.setRange(offset, offset + width, yPlane.bytes, rowStart);
      offset += width;
    }

    final uvRowStride = uPlane.bytesPerRow.toInt();
    final uvPixelStride = (uPlane.bytesPerPixel ?? 1).toInt();
    final chromaHeight = height ~/ 2;
    final chromaWidth = width ~/ 2;

    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final uIndex = (row * uvRowStride + col * uvPixelStride).toInt();
        final vIndex = (row * uvRowStride + col * uvPixelStride).toInt();

        nv21[offset++] = vPlane.bytes[vIndex];
        nv21[offset++] = uPlane.bytes[uIndex];
      }
    }

    final yuvMat = cv.Mat.fromList(
      (height * 1.5).toInt(),
      width,
      cv.MatType.CV_8UC1,
      nv21,
    );

    return cv.cvtColor(yuvMat, cv.COLOR_YUV2BGR_NV21);
  }
}