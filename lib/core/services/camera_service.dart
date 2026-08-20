import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<bool> requestPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<void> initialize() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      throw CameraPermissionDeniedException();
    }

    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw NoCameraAvailableException();
    }

    final backCamera = _cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      backCamera,
      // Was `veryHigh` (1080p+, sometimes 4K depending on device) - every
      // streamed frame gets YUV->BGR converted and run through the full
      // OpenCV detection pipeline synchronously (see DetectionViewModel.
      // onFrame), so resolution is a direct multiplier on per-frame cost.
      // `high` (720p on most devices) is still plenty for card-detail
      // detectors (barcode/fingerprint/logo/flag all run on the already
      // perspective-warped, cropped-to-card-size Mat, not the raw frame),
      // and roughly halves pixel count vs veryHigh on most devices.
      ResolutionPreset.high,
      enableAudio: false,
      // Explicit rather than platform-default: `CameraImageConverter`
      // only has fast paths for these two formats (bgra8888 on iOS,
      // yuv420 on Android repacked to NV21 internally) - letting the
      // platform pick could hand back something the converter falls
      // through on unexpectedly. `camera` only honors this on Android;
      // iOS always delivers bgra8888 regardless of what's requested here.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;

    // Stop the image stream and await it *before* disposing the
    // controller. Previously these two steps were split across two
    // different call sites (`CameraScreen.dispose()` called
    // `stopImageStream()` fire-and-forget, while this method disposed
    // the controller independently, also fire-and-forget) with no
    // ordering between them - a frame in flight when the camera screen
    // was popped could have its callback deliver into an
    // already-disposed controller/view-model tree. Doing both steps here,
    // sequentially, in the same async function guarantees the stream is
    // actually stopped first regardless of what the caller awaits.
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {
        // Already stopped, or the platform side is in a state where
        // stopping is a no-op - either way, still proceed to dispose.
      }
    }
    await controller.dispose();
  }
}

class CameraPermissionDeniedException implements Exception {
  @override
  String toString() => 'Permission caméra refusée par l\'utilisateur.';
}

class NoCameraAvailableException implements Exception {
  @override
  String toString() => 'Aucune caméra disponible sur cet appareil.';
}