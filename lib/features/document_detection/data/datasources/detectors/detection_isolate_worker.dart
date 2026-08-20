import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../../../shared/utils/camera_image_converter.dart';
import '../../../../../shared/utils/detection_stabilizer.dart' show DetectionStabilizer;
import '../../../../image_quality/data/datasources/detectors/blur_detector.dart';
import '../../../../image_quality/data/datasources/detectors/brightness_detector.dart';
import '../../../domain/entities/detected_document.dart';
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
  DetectionIsolateWorker._(
    this._sendPort,
    this._responsePort,
    this._isolate,
    this._errorPort,
    this._exitPort,
  ) : _responses = _responsePort.asBroadcastStream();

  final SendPort _sendPort;
  final ReceivePort _responsePort;
  final Isolate _isolate;
  final ReceivePort _errorPort;
  final ReceivePort _exitPort;
  final Stream<dynamic> _responses;
  int _nextId = 0;

  /// Completes (with an error) if the worker isolate dies unexpectedly -
  /// wired via the `onError`/`onExit` ports passed to `Isolate.spawn` in
  /// [spawn], and listened to for the worker's entire lifetime (not just
  /// during startup). Any request awaiting a reply when that happens
  /// fails fast instead of hanging forever, since a dead isolate will
  /// never send one.
  final Completer<void> _isolateDied = Completer<void>();

  /// How long a single request will wait for a reply before giving up.
  /// Generous relative to normal per-frame processing time (which is on
  /// the order of tens of milliseconds), but still short enough that a
  /// wedged worker surfaces as a visible error instead of an indefinite
  /// hang.
  static const Duration _requestTimeout = Duration(seconds: 10);

  static Future<DetectionIsolateWorker> spawn({
    required String cascadePath,
    required Uint8List logoBytes,
    required Uint8List flagBytes,
  }) async {
    final initPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      initPort.sendPort,
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );

    // First message back from the worker is its SendPort, so we can talk
    // to it - standard two-way isolate handshake.
    final workerSendPort = await initPort.first as SendPort;
    initPort.close();

    final responsePort = ReceivePort();
    workerSendPort.send(responsePort.sendPort);

    final worker = DetectionIsolateWorker._(workerSendPort, responsePort, isolate, errorPort, exitPort);

    // Any uncaught error or unexpected exit on the worker isolate fails
    // every in-flight (and future) request instead of leaving them to
    // hang forever - this is what actually closes the "isolate dies /
    // reply is lost -> future never completes" gap, since a dead isolate
    // will never send the `_Envelope` reply `_request` is waiting on.
    // These listeners stay live for the worker's whole lifetime (closed
    // only in `dispose`), not just during startup - a hang or crash that
    // happens minutes into normal use needs to be caught too.
    errorPort.listen((error) {
      if (!worker._isolateDied.isCompleted) {
        worker._isolateDied.completeError(
          StateError('Le worker de détection a rencontré une erreur fatale : $error'),
        );
      }
    });
    exitPort.listen((_) {
      if (!worker._isolateDied.isCompleted) {
        worker._isolateDied.completeError(
          StateError('Le worker de détection s\'est arrêté de manière inattendue.'),
        );
      }
    });

    // Block until the worker confirms it's finished loading the cascade
    // + templates, so `analyze`/`capture` are never called before the
    // worker is actually ready. Distinguishes `_WorkerReady` from
    // `_WorkerError` - previously this only checked `message.id == -1`
    // regardless of payload type, so a cascade/template load failure at
    // startup still resolved `spawn()` as if the worker were healthy,
    // and every subsequent frame threw once the (never-initialized)
    // detectors were used.
    final ready = Completer<void>();
    late final StreamSubscription sub;
    sub = worker._responses.listen((message) {
      if (message is _Envelope && message.id == -1) {
        sub.cancel();
        final payload = message.payload;
        if (payload is _WorkerError) {
          ready.completeError(StateError(
            'Échec de l\'initialisation du worker de détection : ${payload.error}',
          ));
        } else {
          ready.complete();
        }
      }
    });

    worker._sendPort.send(_Envelope(
      -1,
      _WorkerInit(cascadePath: cascadePath, logoBytes: logoBytes, flagBytes: flagBytes),
    ));

    await Future.any([ready.future, worker._isolateDied.future]);
    return worker;
  }

  Future<IsolateFrameResult> analyze(IsolateFrameInput frame) => _request<IsolateFrameResult>(frame);

  Future<IsolateCaptureResult> capture(IsolateCaptureRequest request) =>
      _request<IsolateCaptureResult>(request);

  Future<void> setSide(CardSide side) async {
    await _request<Object?>(side);
  }

  Future<T> _request<T>(Object payload) async {
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
      // Races the normal reply against isolate death and a hard timeout,
      // so a stuck or vanished worker fails this request instead of
      // leaving it (and `DetectionViewModel._busy`) hung forever with no
      // recovery path.
      return await Future.any<T>([
        completer.future,
        _isolateDied.future.then((_) => throw StateError('Worker de détection indisponible.')),
      ]).timeout(
        _requestTimeout,
        onTimeout: () => throw TimeoutException(
          'Le worker de détection n\'a pas répondu à temps.',
          _requestTimeout,
        ),
      );
    } finally {
      sub.cancel();
    }
  }

  void dispose() {
    // Graceful shutdown: `_WorkerShutdown` makes the worker isolate
    // dispose its own native OpenCV handles (cascade classifier, logo/
    // flag templates - see `_workerMain`'s handling of id == -2) before
    // calling `Isolate.exit()` itself.
    _sendPort.send(_Envelope(-2, _WorkerShutdown()));
    // Closing this main-isolate ReceivePort (not to be confused with the
    // worker-side `commandPort` closed via `Isolate.exit()`) is what
    // actually stops it accumulating: without it, every spawn/dispose
    // cycle (e.g. re-entering the camera screen) left the previous
    // port open and listening forever.
    _responsePort.close();

    // Fallback only: if the worker hasn't actually exited shortly after
    // being asked to (stuck mid-frame, lost the shutdown message, etc.),
    // force it down rather than leaking the isolate forever. Deliberately
    // NOT an immediate kill right away - that could race ahead of the
    // graceful shutdown above and tear the isolate down before it
    // disposes its native handles, reintroducing the very leak this
    // change fixes. `_isolateDied` is already completed by the exit-port
    // listener in [spawn] once the graceful path finishes, so the normal
    // case exits this early via that check and never actually kills
    // anything.
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isolateDied.isCompleted) {
        _isolate.kill(priority: Isolate.immediate);
      }
      _errorPort.close();
      _exitPort.close();
    });
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
        try {
          final init = envelope.payload as _WorkerInit;
          dataSource = DocumentDetectionDataSource(init.cascadePath);
          repository = DetectionRepositoryImpl(dataSource!);
          logoTemplate = repository!.loadTemplateFromBytes(init.logoBytes);
          flagTemplate = repository!.loadTemplateFromBytes(init.flagBytes);
          replyPort.send(const _Envelope(-1, _WorkerReady()));
        } catch (e) {
          // Init failed partway through (e.g. cascade loaded fine but a
          // template didn't) - clean up whatever *did* get allocated
          // before reporting failure, since a failed `spawn()` means
          // `DetectionIsolateWorker.dispose()` never gets called (the
          // caller never got a worker reference to call it on), so this
          // is the only place that partial state would otherwise get
          // cleaned up.
          dataSource?.dispose();
          logoTemplate?.dispose();
          flagTemplate?.dispose();
          replyPort.send(_Envelope(-1, _WorkerError(e.toString())));
        }
        return;
      }

      if (envelope.id == -2) {
        // Release every native OpenCV handle this isolate owns before
        // tearing down - `Isolate.exit()` unwinds the isolate but does
        // nothing to free native (non-Dart-heap) memory itself, so
        // skipping this leaked the face cascade classifier plus the
        // logo/flag templates on every camera-screen re-entry (each of
        // which spawns a fresh worker).
        dataSource?.dispose();
        logoTemplate?.dispose();
        flagTemplate?.dispose();
        commandPort.close();
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
        final result = _captureFrame(payload, repo, currentSide, _matFromFrame);
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
  // `warped` is only rectified, not rotated to right-side-up - unlike the
  // front (which orients via `FaceOrientationDetector` before running its
  // logo/flag checks, see `_analyzeFront` above), the back was previously
  // running these three checks directly on `warped` at whatever rotation
  // the physical card happened to be sitting at. `BarcodeAreaDetector`'s
  // fixed area check tolerates that reasonably well, but
  // `FingerprintPresenceDetector`'s fixed ROI and especially
  // `SeparationLineDetector`'s near-horizontal-only search do not - a
  // card rotated 90 degrees puts the real separation line close to
  // *vertical*, which was getting rejected outright, and the "search on
  // the side" symptom this fixes. `detectBackOrientation` finds the right
  // rotation the same way the front does (try all 4, keep the
  // best-supported one) and returns the barcode/fingerprint/line results
  // already computed at that rotation, so there's no separate "detect,
  // then re-detect at the chosen angle" step needed here.
  final orientation = repository.detectBackOrientation(warped);

  stabilizer.update('barcode', orientation.barcodeFound);
  stabilizer.update('fingerprint', orientation.fingerprintFound);
  // `framesToConfirm: 2` (not the stabilizer's default 3, and NOT 1 - 1
  // was tried and made this flicker green/red rapidly, since it
  // confirmed on a single noisy hit but still needed 2 consecutive
  // misses to un-confirm, an asymmetry that thrashes on a genuinely
  // noisy per-frame Hough-transform signal). 2-in/2-out requires the
  // same number of consecutive frames each direction, so a single stray
  // hit or miss can't flip the state on its own.
  stabilizer.update('separation_line', orientation.separationLineFound, framesToConfirm: 2);

  return BackAnalysisResult(
    document: document,
    rotationDegrees: orientation.rotationDegrees,
    barcodeFound: orientation.barcodeFound,
    barcodeScore: orientation.barcodeScore,
    fingerprintFound: orientation.fingerprintFound,
    fingerprintScore: orientation.fingerprintScore,
    separationLineFound: orientation.separationLineFound,
    separationLineScore: orientation.separationLineScore,
  );
}

IsolateCaptureResult _captureFrame(
  IsolateCaptureRequest request,
  DetectionRepositoryImpl repository,
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

    finalImage = repository.applyRotation(warped, request.rotationDegrees);
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