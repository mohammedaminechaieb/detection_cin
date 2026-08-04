import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/services/camera_service.dart';


class CameraViewModel extends ChangeNotifier {
  final CameraService _cameraService;

  CameraViewModel(this._cameraService);

  bool _isInitialized = false;
  bool _isPermissionGranted = false;
  String? _errorMessage;

  bool get isInitialized => _isInitialized;
  bool get isPermissionGranted => _isPermissionGranted;
  String? get errorMessage => _errorMessage;

  CameraController? get cameraController => _cameraService.controller;

  Future<void> initializeCamera() async {
    try {
      await _cameraService.initialize();
      _isPermissionGranted = true;
      _isInitialized = true;
      _errorMessage = null;
    } catch (e) {
      _isInitialized = false;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }
}
