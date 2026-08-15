import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../../domain/entities/detected_document.dart';
import '../../../image_quality/data/datasources/detectors/brightness_detector.dart';

/// Plain, isolate-safe copy of the parts of a [CameraImage] the detection
/// pipeline actually needs. `CameraImage`/`Plane` themselves wrap
/// platform-side buffers and aren't guaranteed safe to send across an
/// isolate boundary as-is - this pulls out just the raw bytes (already
/// `Uint8List`, which sends cheaply) and the plain metadata needed to
/// reconstruct the YUV/BGRA conversion on the other side.
class IsolateFrameInput {
  const IsolateFrameInput({
    required this.width,
    required this.height,
    required this.isBgra,
    required this.planeBytes,
    required this.planeBytesPerRow,
    required this.planeBytesPerPixel,
  });

  factory IsolateFrameInput.fromCameraImage(CameraImage image) {
    final isBgra = image.format.group == ImageFormatGroup.bgra8888;
    return IsolateFrameInput(
      width: image.width,
      height: image.height,
      isBgra: isBgra,
      planeBytes: [for (final p in image.planes) p.bytes],
      planeBytesPerRow: [for (final p in image.planes) p.bytesPerRow],
      planeBytesPerPixel: [for (final p in image.planes) p.bytesPerPixel ?? 1],
    );
  }

  final int width;
  final int height;
  final bool isBgra;
  final List<Uint8List> planeBytes;
  final List<int> planeBytesPerRow;
  final List<int> planeBytesPerPixel;
}

/// Plain, isolate-safe result of analyzing one frame - everything
/// `DetectionViewModel` needs to update its state and feed
/// `AutocaptureViewModel`, with no `cv.Mat` or other native handles.
///
/// Does NOT include the captured PNG bytes: whether this frame is "the"
/// capture frame is a decision that depends on `AutocaptureViewModel`'s
/// streak state, which lives on the main isolate (it's a `ChangeNotifier`
/// the UI listens to) - the worker has no way to know that on its own.
/// When `DetectionViewModel` sees the state flip to `captured`, it sends
/// a separate [IsolateCaptureRequest] for that same frame, carrying the
/// rotation to apply - see `DetectionIsolateWorker.capture`.
class IsolateFrameResult {
  const IsolateFrameResult({
    required this.document,
    required this.frontResult,
    required this.backResult,
    required this.sharpnessScore,
    required this.brightness,
    required this.processingMicros,
    required this.isBorderDetected,
    required this.isFaceDetected,
    required this.isLogoDetected,
    required this.isFlagDetected,
    required this.isBarcodeDetected,
    required this.isFingerprintDetected,
    required this.isSeparationLineDetected,
    required this.contentMatched,
  });

  final DetectedDocument document;
  final CardAnalysisResult? frontResult;
  final BackAnalysisResult? backResult;
  final double sharpnessScore;
  final BrightnessStatus brightness;
  final int processingMicros;

  // Already run through `DetectionStabilizer` inside the worker (see
  // `DetectionIsolateWorker`'s entry point) - the stabilizer is pure Dart
  // with no `cv.Mat` dependency, but it lives on the worker side rather
  // than the main isolate because the raw per-signal booleans it needs
  // are a byproduct of `_analyzeFront`/`_analyzeBack`, which already run
  // there; sending the stabilized result back avoids re-deriving
  // anything from raw data on the main isolate.
  final bool isBorderDetected;
  final bool isFaceDetected;
  final bool isLogoDetected;
  final bool isFlagDetected;
  final bool isBarcodeDetected;
  final bool isFingerprintDetected;
  final bool isSeparationLineDetected;

  /// Whether the content checks specific to the analyzed side all passed
  /// this frame (logo+flag for front; barcode+fingerprint+separation
  /// line for back). Computed here, inside the worker, using the
  /// *stabilized* separation-line signal (`isSeparationLineDetected`
  /// above) rather than the raw per-frame Hough result - see the comment
  /// on `_analyzeBack`'s `stabilizer.update('separation_line', ...)`
  /// call for why that distinction matters (it's what was causing the
  /// back capture to take much longer than the front).
  final bool contentMatched;
}

/// Sent from the main isolate once `AutocaptureViewModel` has just
/// transitioned into `CaptureState.captured` for [frame], asking the
/// worker to re-run detection + warp on that exact frame and encode the
/// upright result. Carrying [frame] again (rather than trying to keep the
/// previous frame's `cv.Mat` alive inside the worker across messages)
/// keeps the worker's per-message handling stateless and simple, at the
/// cost of redoing the contour search once more for this one frame -
/// negligible next to camera frame-rate timing.
class IsolateCaptureRequest {
  const IsolateCaptureRequest({required this.frame, required this.rotationDegrees});

  final IsolateFrameInput frame;

  /// The rotation to apply before encoding - for the front this is
  /// `CardAnalysisResult.photo.rotationDegrees`; for the back,
  /// `BackAnalysisResult.rotationDegrees` (see `BackOrientationDetector`).
  /// Either way it's a value already computed during this frame's regular
  /// analysis and just passed back through, not re-derived here.
  final int rotationDegrees;
}

/// Result of an [IsolateCaptureRequest] - `pngBytes` is null if the card
/// couldn't be re-detected on this frame (shouldn't normally happen,
/// since the main isolate only asks for this right after that same frame
/// analyzed successfully, but frame-to-frame state on the worker side -
/// e.g. `DocumentContourDetector`'s tracked quad - could in principle
/// have shifted between the two calls).
class IsolateCaptureResult {
  const IsolateCaptureResult({this.pngBytes});

  final Uint8List? pngBytes;
}