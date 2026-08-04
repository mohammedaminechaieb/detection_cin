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
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    await _controller!.initialize();
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
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
