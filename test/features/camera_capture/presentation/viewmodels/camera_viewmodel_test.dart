import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:detection_cin/core/services/camera_service.dart';
import 'package:detection_cin/features/camera_capture/presentation/viewmodels/camera_viewmodel.dart';

class MockCameraService extends Mock implements CameraService {}

void main() {
  late MockCameraService mockService;
  late CameraViewModel viewModel;

  setUp(() {
    mockService = MockCameraService();
    viewModel = CameraViewModel(mockService);
  });

  test('état initial : non initialisé, pas de permission, pas d\'erreur', () {
    expect(viewModel.isInitialized, false);
    expect(viewModel.isPermissionGranted, false);
    expect(viewModel.errorMessage, null);
  });

  test('initializeCamera() : succès → isInitialized devient true', () async {
    when(() => mockService.initialize()).thenAnswer((_) async {});

    await viewModel.initializeCamera();

    expect(viewModel.isInitialized, true);
    expect(viewModel.errorMessage, null);
    verify(() => mockService.initialize()).called(1);
  });

  test('initializeCamera() : permission refusée → erreur exposée', () async {
    when(() => mockService.initialize())
        .thenThrow(CameraPermissionDeniedException());

    await viewModel.initializeCamera();

    expect(viewModel.isInitialized, false);
    expect(viewModel.errorMessage, contains('Permission caméra'));
  });

  test('initializeCamera() : aucune caméra dispo → erreur exposée', () async {
    when(() => mockService.initialize())
        .thenThrow(NoCameraAvailableException());

    await viewModel.initializeCamera();

    expect(viewModel.isInitialized, false);
    expect(viewModel.errorMessage, contains('Aucune caméra'));
  });
}
