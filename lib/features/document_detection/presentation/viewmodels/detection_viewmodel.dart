import 'package:camera/camera.dart';
import 'package:detection_cin/features/image_quality/data/datasources/detectors/brightness_detector.dart';
import 'package:flutter/foundation.dart';

import '../../data/datasources/detectors/detection_isolate_worker.dart';
import '../../data/datasources/isolate_frame_messages.dart';
import '../../domain/entities/detected_document.dart';
import '../../../autocapture/domain/entities/capture_state.dart';
import '../../../autocapture/domain/entities/quality_report.dart';
import '../../domain/repositories/detection_repository.dart';
import '../../../autocapture/presentation/viewmodels/autocapture_viewmodel.dart';
import '../../../image_quality/data/datasources/detectors/stability_tracker.dart';

/// Drives the live camera analysis loop.
///
/// The actual OpenCV work (frame conversion, contour detection, content
/// checks) runs on a persistent background isolate owned by
/// [DetectionIsolateWorker] - this class's job is just to extract plain
/// data from each [CameraImage], hand it to the worker, and turn the
/// plain result back into UI-facing state. This used to all run
/// synchronously on the platform thread (the same thread driving camera
/// preview rendering), which was the actual cause of the camera lag: a
/// slow detection pass blocked preview rendering for exactly as long as
/// it took. See `DetectionIsolateWorker`'s class doc for why a plain
/// `compute()` per frame wasn't viable here instead.
///
/// [StabilityTracker] (quad-position jitter, not to be confused with
/// [DetectionStabilizer] inside the worker, which smooths individual
/// boolean signals like "logo found") stays here on the main isolate: it
/// only needs the already-plain [CardQuad] from each result, so there's
/// no reason to add it to the worker's surface.
class DetectionViewModel extends ChangeNotifier {
  DetectionViewModel(
    this.repository, {
    StabilityTracker? stabilityTracker,
    this.autocaptureViewModel,
  }) : _stabilityTracker = stabilityTracker ?? StabilityTracker();

  final DetectionRepository repository;
  final StabilityTracker _stabilityTracker;

  /// Optional - if provided, [onFrame] feeds it a [QualityReport] every
  /// analyzed frame so it can drive the Step 3 autocapture state machine.
  final AutocaptureViewModel? autocaptureViewModel;

  /// Fired exactly once per capture cycle, the frame [autocaptureViewModel]
  /// transitions into [CaptureState.captured] - carries the PNG-encoded
  /// warped card for that side. `null` if no [autocaptureViewModel] was
  /// provided (nothing will ever fire).
  void Function(Uint8List pngBytes, CardSide side)? onCardCaptured;

  DetectionIsolateWorker? _worker;

  /// Must be called once (and awaited) before [onFrame] is used - spawns
  /// the background isolate and loads the cascade/templates into it.
  /// Mirrors what used to happen synchronously in this class's
  /// constructor + `loadTemplates`.
  Future<void> initialize({
    required String cascadePath,
    required Uint8List logoBytes,
    required Uint8List flagBytes,
  }) async {
    _worker = await DetectionIsolateWorker.spawn(
      cascadePath: cascadePath,
      logoBytes: logoBytes,
      flagBytes: flagBytes,
    );
  }

  CardSide _currentSide = CardSide.front;
  CardSide get currentSide => _currentSide;

  // Bumped on every `setSide` call. `onFrame` captures the generation a
  // frame was sent under and compares it after the (async) worker
  // round-trip - if `setSide` happened while that frame was in flight,
  // the reply is discarded rather than applied under the wrong side
  // (`result.frontResult`/`backResult` reflects whichever side the
  // worker's `currentSide` was set to *when it processed that frame*,
  // which is correct on the worker side, but could now disagree with
  // this class's `_currentSide` by the time the reply arrives here).
  int _sideGeneration = 0;

  void setSide(CardSide side) {
    _currentSide = side;
    _sideGeneration++;
    _stabilityTracker.reset();
    _isBorderDetected = false;
    _isFaceDetected = false;
    _isLogoDetected = false;
    _isFlagDetected = false;
    _isBarcodeDetected = false;
    _isFingerprintDetected = false;
    _isSeparationLineDetected = false;
    _worker?.setSide(side);
    notifyListeners();
  }

  CardAnalysisResult _lastFrontResult = CardAnalysisResult.none();
  BackAnalysisResult _lastBackResult = BackAnalysisResult.none();
  CardAnalysisResult get lastFrontResult => _lastFrontResult;
  BackAnalysisResult get lastBackResult => _lastBackResult;

  // Mirrors the worker's stabilized flags from the most recent result -
  // see `IsolateFrameResult`.
  bool _isBorderDetected = false;
  bool _isFaceDetected = false;
  bool _isLogoDetected = false;
  bool _isFlagDetected = false;
  bool _isBarcodeDetected = false;
  bool _isFingerprintDetected = false;
  bool _isSeparationLineDetected = false;

  bool get isBorderDetected => _isBorderDetected;
  bool get isFaceDetected => _isFaceDetected;
  bool get isLogoDetected => _isLogoDetected;
  bool get isFlagDetected => _isFlagDetected;
  bool get isBarcodeDetected => _isBarcodeDetected;
  bool get isFingerprintDetected => _isFingerprintDetected;
  bool get isSeparationLineDetected => _isSeparationLineDetected;

  /// Fires after every analyzed frame with how long the worker took to
  /// process it - round-trip isolate messaging time is not included,
  /// only the worker's own processing (see `IsolateFrameResult.
  /// processingMicros`), so this reflects actual OpenCV cost rather than
  /// isolate communication overhead. Wire this to a debug overlay or
  /// `debugPrint` when chasing performance.
  void Function(Duration elapsed)? onFrameDuration;

  /// Guards against overlapping frames the same way `_busy` did in the
  /// old synchronous implementation - since `analyze` now means "sent to
  /// the worker, awaiting a reply" rather than "running inline", this
  /// naturally paces frames to however fast the worker can actually keep
  /// up, without needing a separate wall-clock throttle.
  bool _busy = false;

  Future<void> onFrame(CameraImage image) async {
    final worker = _worker;
    if (worker == null || _busy) return;

    _busy = true;
    final sentUnderGeneration = _sideGeneration;
    try {
      final frame = IsolateFrameInput.fromCameraImage(image);
      final result = await worker.analyze(frame);

      if (sentUnderGeneration != _sideGeneration) {
        // `setSide` was called while this frame was in flight - discard
        // rather than risk applying `result.frontResult`/`backResult`
        // (populated for whichever side was active *when the worker
        // processed it*) under a `_currentSide` that's since changed.
        // `setSide` already reset the UI-facing flags/trackers, so there
        // is nothing stale left to clean up here.
        return;
      }

      onFrameDuration?.call(Duration(microseconds: result.processingMicros));

      _isBorderDetected = result.isBorderDetected;
      _isFaceDetected = result.isFaceDetected;
      _isLogoDetected = result.isLogoDetected;
      _isFlagDetected = result.isFlagDetected;
      _isBarcodeDetected = result.isBarcodeDetected;
      _isFingerprintDetected = result.isFingerprintDetected;
      _isSeparationLineDetected = result.isSeparationLineDetected;

      if (!result.document.isDetected || result.document.quad == null) {
        _stabilityTracker.reset();
        if (_currentSide == CardSide.front) {
          _lastFrontResult = CardAnalysisResult.none();
        } else {
          _lastBackResult = BackAnalysisResult.none();
        }
        autocaptureViewModel?.onFrame(const QualityReport(
          quadFound: false,
          sharpnessScore: 0,
          brightness: BrightnessStatus.ok,
          isStable: false,
          contentMatched: false,
        ));
        notifyListeners();
        return;
      }

      if (_currentSide == CardSide.front) {
        _lastFrontResult = result.frontResult!;
      } else {
        _lastBackResult = result.backResult!;
      }

      _stabilityTracker.update(result.document.quad!.toOffsets());
      final report = QualityReport(
        quadFound: true,
        sharpnessScore: result.sharpnessScore,
        brightness: result.brightness,
        isStable: _stabilityTracker.isStable,
        contentMatched: result.contentMatched,
      );

      final wasCaptured = autocaptureViewModel?.state == CaptureState.captured;
      autocaptureViewModel?.onFrame(report);
      final justCaptured = !wasCaptured && autocaptureViewModel?.state == CaptureState.captured;
      if (justCaptured) {
        // Front already knows its rotation cheaply (from face detection,
        // already computed as part of this frame's analysis); back has
        // no face to anchor on, so pass `null` and let the worker run
        // the one-time 4-rotation search inside `capture` instead (see
        // `DetectBackOrientation` - still deliberately NOT run every
        // frame, only on this explicit capture request).
        final rotationDegrees =
            _currentSide == CardSide.front ? _lastFrontResult.photo.rotationDegrees : null;
        final captureResult = await worker.capture(
          IsolateCaptureRequest(frame: frame, rotationDegrees: rotationDegrees),
        );
        if (captureResult.pngBytes != null && sentUnderGeneration == _sideGeneration) {
          onCardCaptured?.call(captureResult.pngBytes!, _currentSide);
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Erreur detection frame: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }
}