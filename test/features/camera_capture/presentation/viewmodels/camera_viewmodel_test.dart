// Tier B - mocks CameraService (mocktail) so the camera plugin's real
// platform channel is never touched. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:detection_cin/core/services/camera_service.dart';
import 'package:detection_cin/features/camera_capture/presentation/viewmodels/camera_viewmodel.dart';

class MockCameraService extends Mock implements CameraService {}

void main() {
  group('CameraViewModel', () {
    test('initial state is not initialized, no permission, no error', () {
      final vm = CameraViewModel(MockCameraService());
      expect(vm.isInitialized, isFalse);
      expect(vm.isPermissionGranted, isFalse);
      expect(vm.errorMessage, isNull);
      expect(vm.setupError, CameraSetupError.none);
    });

    test('successful initialize() sets isInitialized/isPermissionGranted true and clears error', () async {
      final service = MockCameraService();
      when(() => service.initialize()).thenAnswer((_) async {});
      final vm = CameraViewModel(service);

      await vm.initializeCamera();

      expect(vm.isInitialized, isTrue);
      expect(vm.isPermissionGranted, isTrue);
      expect(vm.errorMessage, isNull);
      expect(vm.setupError, CameraSetupError.none);
      verify(() => service.initialize()).called(1);
    });

    test('CameraPermissionDeniedException maps to setupError.permissionDenied', () async {
      final service = MockCameraService();
      when(() => service.initialize()).thenThrow(CameraPermissionDeniedException());
      final vm = CameraViewModel(service);

      await vm.initializeCamera();

      expect(vm.isInitialized, isFalse);
      expect(vm.setupError, CameraSetupError.permissionDenied);
      expect(vm.errorMessage, isNotNull);
    });

    test('NoCameraAvailableException maps to setupError.noCameraAvailable', () async {
      final service = MockCameraService();
      when(() => service.initialize()).thenThrow(NoCameraAvailableException());
      final vm = CameraViewModel(service);

      await vm.initializeCamera();

      expect(vm.setupError, CameraSetupError.noCameraAvailable);
    });

    test('any other exception maps to setupError.unknown', () async {
      final service = MockCameraService();
      when(() => service.initialize()).thenThrow(StateError('boom'));
      final vm = CameraViewModel(service);

      await vm.initializeCamera();

      expect(vm.setupError, CameraSetupError.unknown);
      expect(vm.errorMessage, contains('boom'));
    });

    test('initializeCamera() always notifies listeners exactly once per call', () async {
      final service = MockCameraService();
      when(() => service.initialize()).thenAnswer((_) async {});
      final vm = CameraViewModel(service);

      var notified = 0;
      vm.addListener(() => notified++);
      await vm.initializeCamera();

      expect(notified, 1);
    });

    test('dispose() delegates to CameraService.dispose()', () {
      final service = MockCameraService();
      when(() => service.dispose()).thenAnswer((_) async {});
      final vm = CameraViewModel(service);

      vm.dispose();

      verify(() => service.dispose()).called(1);
    });

    test('cameraController getter forwards to the underlying service', () {
      final service = MockCameraService();
      when(() => service.controller).thenReturn(null);
      final vm = CameraViewModel(service);

      expect(vm.cameraController, isNull);
      verify(() => service.controller).called(1);
    });
  });
}
