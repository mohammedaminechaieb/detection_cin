import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/services/camera_service.dart';

/// Distinguishes *why* camera setup failed, so the UI can offer the
/// right recovery action instead of a generic error (e.g. "Open
/// Settings" only makes sense for a permission denial, not for "no
/// camera hardware").
enum CameraSetupError { none, permissionDenied, noCameraAvailable, unknown }

class CameraViewModel extends ChangeNotifier {
  final CameraService _cameraService;

  CameraViewModel(this._cameraService);

  bool _isInitialized = false;
  bool _isPermissionGranted = false;
  String? _errorMessage;
  CameraSetupError _setupError = CameraSetupError.none;

  bool get isInitialized => _isInitialized;
  bool get isPermissionGranted => _isPermissionGranted;
  String? get errorMessage => _errorMessage;
  CameraSetupError get setupError => _setupError;

  CameraController? get cameraController => _cameraService.controller;

  Future<void> initializeCamera() async {
    try {
      await _cameraService.initialize();
      _isPermissionGranted = true;
      _isInitialized = true;
      _errorMessage = null;
      _setupError = CameraSetupError.none;
    } on CameraPermissionDeniedException catch (e) {
      _isInitialized = false;
      _errorMessage = e.toString();
      _setupError = CameraSetupError.permissionDenied;
    } on NoCameraAvailableException catch (e) {
      _isInitialized = false;
      _errorMessage = e.toString();
      _setupError = CameraSetupError.noCameraAvailable;
    } catch (e) {
      _isInitialized = false;
      _errorMessage = e.toString();
      _setupError = CameraSetupError.unknown;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }
}