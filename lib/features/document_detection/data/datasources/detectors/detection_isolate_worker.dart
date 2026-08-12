import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../../../shared/utils/camera_image_converter.dart';
import '../../../../../shared/utils/detection_stabilizer.dart' show DetectionStabilizer;
import '../../../../image_quality/data/datasources/detectors/blur_detector.dart';
import '../../../../image_quality/data/datasources/detectors/brightness_detector.dart';
import '../../../domain/entities/detected_document.dart';
import '../../../domain/usecases/detect_back_orientation.dart';
import '../../repositories/detection_repository_impl.dart';
import '../document_detection_datasource.dart';
import '../isolate_frame_messages.dart';

/// Message sent once, at worker startup, to load the cascade classifier
/// and logo/flag templates before any frames are processed.
class _WorkerInit {
  const _WorkerInit({
    required this.cascadePath,
    required this.logoBytes,
    required this.flagBytes,
  });
  final String cascadePath;
  final Uint8List logoBytes;
  final Uint8List flagBytes;
}

/// Wraps a request with a small correlation id so the main isolate can
/// match each reply back to the `Future` that's awaiting it - frames can
/// in principle be sent faster than replies come back (though
/// `DetectionIsolateWorker.analyze`'s single in-flight guard prevents
/// that in practice, see below), so replies aren't assumed to arrive in
/// the same order requests were sent.
class _Envelope {
  const _Envelope(this.id, this.payload);
  final int id;
  final Object? payload;
}

/// Owns the entire OpenCV detection pipeline on a background isolate, so
/// the (expensive, synchronous) contour/content detection work never
/// blocks the platform thread that also drives camera preview rendering.
///
/// This was the actual root cause of the camera lag: `DetectionViewModel.
/// onFrame` used to run the full convert+detect pipeline synchronously on
/// the platform thread, directly inside the `camera` plugin's image
/// stream callback. A slow frame blocked preview rendering for exactly
/// as long as detection took.
///
/// A plain `compute()` call per frame was considered and rejected: it
/// spins up a fresh isolate (or reuses a pool one) that has to rebuild
/// all its state from scratch, and this pipeline's state genuinely can't
/// be cheaply rebuilt every frame - `FaceOrientationDetector` loads a
/// Haar cascade from disk, `TemplateMatcher`'s logo/flag templates get
/// decoded from bytes, and `DocumentContourDetector` needs its tracked
/// quad to persist frame-to-frame for the cheap "search near last known
/// position" path to work at all (see its class doc). Reloading the
/// cascade and templates on every frame would likely cost more than the
/// synchronous approach did. A *persistent* isolate that loads all of
/// that exactly once and then just receives frames avoids all of that.
class DetectionIsolateWorker {
  DetectionIsolateWorker._(this._sendPort, this._responses);

  final SendPort _sendPort;
  final Stream<dynamic> _responses;
  int _nextId = 0;

  /// True while a frame is in flight to the worker - `DetectionViewModel`
  /// uses this indirectly (it only calls [analyze] when not already
  /// awaiting one) so frames are naturally paced by how fast the worker
  /// can actually process them, the same throttling role `_busy` played
  /// in the old synchronous `onFrame`.
  bool get isBusy => _busy;
  bool _busy = false;

  static Future<DetectionIsolateWorker> spawn({
    required String cascadePath,
    required Uint8List logoBytes,
    required Uint8List flagBytes,
  }) async {
    final initPort = ReceivePort();
    await Isolate.spawn(_workerMain, initPort.sendPort);

    // First message back from the worker is its SendPort, so we can talk
    // to it - standard two-way isolate handshake.
    final workerSendPort = await initPort.first as SendPort;
    initPort.close();

    final responsePort = ReceivePort();
    workerSendPort.send(responsePort.sendPort);

    final worker = DetectionIsolateWorker._(workerSendPort, responsePort.asBroadcastStream());

    // Block until the worker confirms it's finished loading the cascade
    // + templates, so `analyze`/`capture` are never called before the
    // worker is actually ready.
    final ready = Completer<void>();
    late final StreamSubscription sub;
    sub = worker._responses.listen((message) {
      if (message is _Envelope && message.id == -1) {
        ready.complete();
        sub.cancel();
      }
    });

    worker._sendPort.send(_Envelope(
      -1,
      _WorkerInit(cascadePath: cascadePath, logoBytes: logoBytes, flagBytes: flagBytes),
    ));

    await ready.future;
    return worker;
  }

  Future<IsolateFrameResult> analyze(IsolateFrameInput frame) => _request<IsolateFrameResult>(frame);

  Future<IsolateCaptureResult> capture(IsolateCaptureRequest request) =>
      _request<IsolateCaptureResult>(request);

  Future<void> setSide(CardSide side) async {
    await _request<Object?>(side);
  }

  Future<T> _request<T>(Object payload) async {
    _busy = true;
    final id = _nextId++;
    final completer = Completer<T>();

    late final StreamSubscription sub;
    sub = _responses.listen((message) {
      if (message is _Envelope && message.id == id) {
        sub.cancel();
        final result = message.payload;
        if (result is _WorkerError) {
          completer.completeError(result.error);
        } else {
          completer.complete(result as T);
        }
      }
    });

    _sendPort.send(_Envelope(id, payload));

    try {
      return await completer.future;
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _sendPort.send(_Envelope(-2, _WorkerShutdown()));
  }
}

class _WorkerShutdown {}

class _WorkerError {
  const _WorkerError(this.error);
  final String error;
}

/// Entry point run on the background isolate. Owns everything that was
/// previously instance state on `DetectionViewModel`/`DocumentDetection
/// DataSource`: the cascade classifier, templates, and the contour
/// tracker's persisted quad - all loaded/created exactly once here, not
/// per frame.
void _workerMain(SendPort initSendPort) {
  final commandPort = ReceivePort();
  initSendPort.send(commandPort.sendPort);

  const converter = CameraImageConverter();
  final stabilizer = DetectionStabilizer();
  const blurDetector = BlurDetector();
  const brightnessDetector = BrightnessDetector();

  DocumentDetectionDataSource? dataSource;
  DetectionRepositoryImpl? repository;
  DetectBackOrientation? detectBackOrientation;
  cv.Mat? logoTemplate;
  cv.Mat? flagTemplate;
  var currentSide = CardSide.front;

  late final SendPort replyPort;

  cv.Mat _matFromFrame(IsolateFrameInput frame) => converter.toBgrMat(
        width: frame.width,
        height: frame.height,
        isBgra: frame.isBgra,
        planeBytes: frame.planeBytes,
        planeBytesPerRow: frame.planeBytesPerRow,
        planeBytesPerPixel: frame.planeBytesPerPixel,
      );

  commandPort.listen((message) {
    if (message is SendPort) {
      replyPort = message;
      return;
    }

    final envelope = message as _Envelope;

    try {
      if (envelope.id == -1) {
        final init = envelope.payload as _WorkerInit;
        dataSource = DocumentDetectionDataSource(init.cascadePath);
        repository = DetectionRepositoryImpl(dataSource!);
        detectBackOrientation = DetectBackOrientation(repository!);
        logoTemplate = repository!.loadTemplateFromBytes(init.logoBytes);
        flagTemplate = repository!.loadTemplateFromBytes(init.flagBytes);
        replyPort.send(const _Envelope(-1, _WorkerReady()));
        return;
      }

      if (envelope.id == -2) {
        Isolate.exit();
      }

      final payload = envelope.payload;
      final repo = repository!;

      if (payload is CardSide) {
        currentSide = payload;
        repo.resetTracking();
        stabilizer.resetAll();
        replyPort.send(_Envelope(envelope.id, null));
        return;
      }

      if (payload is IsolateFrameInput) {
        final result = _analyzeFrame(
          payload,
          repo,
          stabilizer,
          blurDetector,
          brightnessDetector,
          logoTemplate!,
          flagTemplate!,
          currentSide,
          _matFromFrame,
        );
        replyPort.send(_Envelope(envelope.id, result));
        return;
      }

      if (payload is IsolateCaptureRequest) {
        final result = _captureFrame(payload, repo, detectBackOrientation!, currentSide, _matFromFrame);
        replyPort.send(_Envelope(envelope.id, result));
        return;
      }
    } catch (e) {
      replyPort.send(_Envelope(envelope.id, _WorkerError(e.toString())));
    }
  });
}

class _WorkerReady {
  const _WorkerReady();
}

IsolateFrameResult _analyzeFrame(
  IsolateFrameInput frame,
  DetectionRepositoryImpl repository,
  DetectionStabilizer stabilizer,
  BlurDetector blurDetector,
  BrightnessDetector brightnessDetector,
  cv.Mat logoTemplate,
  cv.Mat flagTemplate,
  CardSide currentSide,
  cv.Mat Function(IsolateFrameInput) matFromFrame,
) {
  final stopwatch = Stopwatch()..start();
  final mat = matFromFrame(frame);
  cv.Mat? warped;

  try {
    final document = repository.detectDocument(mat);

    if (!document.isDetected || document.quad == null) {
      stabilizer.resetAll();
      return IsolateFrameResult(
        document: DetectedDocument.none(),
        frontResult: currentSide == CardSide.front ? CardAnalysisResult.none() : null,
        backResult: currentSide == CardSide.back ? BackAnalysisResult.none() : null,
        sharpnessScore: 0,
        brightness: BrightnessStatus.ok,
        processingMicros: stopwatch.elapsedMicroseconds,
        isBorderDetected: false,
        isFaceDetected: false,
        isLogoDetected: false,
        isFlagDetected: false,
        isBarcodeDetected: false,
        isFingerprintDetected: false,
        isSeparationLineDetected: false,
        contentMatched: false,
      );
    }

    warped = repository.warpDocument(mat, document.quad!);
    stabilizer.update('border', document.isDetected);

    final frontResult = currentSide == CardSide.front
        ? _analyzeFront(document, warped, repository, logoTemplate, flagTemplate, stabilizer)
        : null;
    final backResult =
        currentSide == CardSide.back ? _analyzeBack(document, warped, repository, stabilizer) : null;

    final isSeparationLineDetected = stabilizer.isStable('separation_line');
    final contentMatched = currentSide == CardSide.front
        ? (frontResult!.logoFound && frontResult.flagFound)
        : (backResult!.barcodeFound && backResult.fingerprintFound && isSeparationLineDetected);

    return IsolateFrameResult(
      document: document,
      frontResult: frontResult,
      backResult: backResult,
      sharpnessScore: blurDetector.sharpnessScore(warped),
      brightness: brightnessDetector.classify(warped),
      processingMicros: stopwatch.elapsedMicroseconds,
      isBorderDetected: stabilizer.isStable('border'),
      isFaceDetected: stabilizer.isStable('face'),
      isLogoDetected: stabilizer.isStable('logo'),
      isFlagDetected: stabilizer.isStable('flag'),
      isBarcodeDetected: stabilizer.isStable('barcode'),
      isFingerprintDetected: stabilizer.isStable('fingerprint'),
      isSeparationLineDetected: isSeparationLineDetected,
      contentMatched: contentMatched,
    );
  } finally {
    warped?.dispose();
    mat.dispose();
  }
}

CardAnalysisResult _analyzeFront(
  DetectedDocument document,
  cv.Mat warped,
  DetectionRepositoryImpl repository,
  cv.Mat logoTemplate,
  cv.Mat flagTemplate,
  DetectionStabilizer stabilizer,
) {
  final (photo, faceBox) = repository.detectPhoto(warped);
  final oriented = repository.applyRotation(warped, photo.rotationDegrees);

  final (logoFound, logoScore) = repository.detectLogo(oriented, logoTemplate);
  final (flagFound, flagScore) = repository.detectFlag(oriented, flagTemplate);

  if (!identical(oriented, warped)) {
    oriented.dispose();
  }

  stabilizer.update('face', photo.found);
  stabilizer.update('logo', logoFound);
  stabilizer.update('flag', flagFound);

  return CardAnalysisResult(
    document: document,
    photo: photo,
    faceBox: faceBox,
    logoFound: logoFound,
    logoScore: logoScore,
    flagFound: flagFound,
    flagScore: flagScore,
  );
}

BackAnalysisResult _analyzeBack(
  DetectedDocument document,
  cv.Mat warped,
  DetectionRepositoryImpl repository,
  DetectionStabilizer stabilizer,
) {
  final (barcodeFound, barcodeScore) = repository.detectBarcodePresence(warped);
  final (fingerprintFound, fingerprintScore) = repository.detectFingerprintPresence(warped);
  final (lineFound, _, lineScore) = repository.detectSeparationLine(warped);

  stabilizer.update('barcode', barcodeFound);
  stabilizer.update('fingerprint', fingerprintFound);
  // `framesToConfirm: 2` (not the stabilizer's default 3, and NOT 1 - 1
  // was tried and made this flicker green/red rapidly, since it
  // confirmed on a single noisy hit but still needed 2 consecutive
  // misses to un-confirm, an asymmetry that thrashes on a genuinely
  // noisy per-frame Hough-transform signal). 2-in/2-out requires the
  // same number of consecutive frames each direction, so a single stray
  // hit or miss can't flip the state on its own.
  stabilizer.update('separation_line', lineFound, framesToConfirm: 2);

  return BackAnalysisResult(
    document: document,
    barcodeFound: barcodeFound,
    barcodeScore: barcodeScore,
    fingerprintFound: fingerprintFound,
    fingerprintScore: fingerprintScore,
    separationLineFound: lineFound,
    separationLineScore: lineScore,
  );
}

IsolateCaptureResult _captureFrame(
  IsolateCaptureRequest request,
  DetectionRepositoryImpl repository,
  DetectBackOrientation detectBackOrientation,
  CardSide currentSide,
  cv.Mat Function(IsolateFrameInput) matFromFrame,
) {
  final mat = matFromFrame(request.frame);
  cv.Mat? warped;
  cv.Mat? finalImage;

  try {
    final document = repository.detectDocument(mat);
    if (!document.isDetected || document.quad == null) {
      return const IsolateCaptureResult(pngBytes: null);
    }

    warped = repository.warpDocument(mat, document.quad!);

    final rotationDegrees = request.rotationDegrees ?? detectBackOrientation(warped).$1;
    finalImage = repository.applyRotation(warped, rotationDegrees);
    final pngBytes = repository.encodeToPng(finalImage);
    return IsolateCaptureResult(pngBytes: pngBytes);
  } finally {
    if (finalImage != null && !identical(finalImage, warped)) {
      finalImage.dispose();
    }
    warped?.dispose();
    mat.dispose();
  }
}