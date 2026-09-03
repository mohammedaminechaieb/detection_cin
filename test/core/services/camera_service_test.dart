// Tier B - swaps out CameraPlatform.instance and
// PermissionHandlerPlatform.instance with in-memory fakes, the same
// technique the plugins themselves recommend for testing code built on
// top of them, so this runs on a plain host without a device or
// emulator. See test/README.md.
//
// ASSOMPTION NON VÉRIFIÉE: exact camera_platform_interface /
// permission_handler_platform_interface method signatures below match
// the versions pinned in pubspec.yaml - both plugins have shifted this
// surface across major versions. Adjust the overrides if
// `flutter analyze` flags a signature mismatch.
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:detection_cin/core/services/camera_service.dart';

class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform(this.cameras);

  final List<CameraDescription> cameras;
  bool initializeCalled = false;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    return 0;
  }

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    initializeCalled = true;
  }

  @override
  Future<void> dispose(int cameraId) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(cameraId, 1280, 720, ExposureMode.auto, true, FocusMode.auto, true));

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) => const Stream.empty();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();
}

class _FakePermissionHandlerPlatform extends PermissionHandlerPlatform {
  _FakePermissionHandlerPlatform(this.statusToReturn);

  final PermissionStatus statusToReturn;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async => statusToReturn;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(List<Permission> permissions) async {
    return {for (final p in permissions) p: statusToReturn};
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(Permission permission) async => false;

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async => ServiceStatus.enabled;

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraService.requestPermission', () {
    test('returns true when the platform reports granted', () async {
      PermissionHandlerPlatform.instance = _FakePermissionHandlerPlatform(PermissionStatus.granted);
      final service = CameraService();
      expect(await service.requestPermission(), isTrue);
    });

    test('returns false when the platform reports denied', () async {
      PermissionHandlerPlatform.instance = _FakePermissionHandlerPlatform(PermissionStatus.denied);
      final service = CameraService();
      expect(await service.requestPermission(), isFalse);
    });
  });

  group('CameraService.initialize', () {
    test('throws CameraPermissionDeniedException when permission is denied', () async {
      PermissionHandlerPlatform.instance = _FakePermissionHandlerPlatform(PermissionStatus.denied);
      final service = CameraService();
      expect(() => service.initialize(), throwsA(isA<CameraPermissionDeniedException>()));
    });

    test('throws NoCameraAvailableException when the platform has no cameras', () async {
      PermissionHandlerPlatform.instance = _FakePermissionHandlerPlatform(PermissionStatus.granted);
      CameraPlatform.instance = _FakeCameraPlatform([]);
      final service = CameraService();
      expect(() => service.initialize(), throwsA(isA<NoCameraAvailableException>()));
    });

    test('isInitialized is false before initialize() and controller is null', () {
      final service = CameraService();
      expect(service.isInitialized, isFalse);
      expect(service.controller, isNull);
    });
  });

  group('CameraService.dispose', () {
    test('is safe to call before initialize()', () async {
      final service = CameraService();
      await expectLater(service.dispose(), completes);
      expect(service.controller, isNull);
    });
  });

  group('exception messages', () {
    test('CameraPermissionDeniedException has a human-readable French message', () {
      expect(CameraPermissionDeniedException().toString(), contains('Permission caméra refusée'));
    });

    test('NoCameraAvailableException has a human-readable French message', () {
      expect(NoCameraAvailableException().toString(), contains('Aucune caméra disponible'));
    });
  });
}
