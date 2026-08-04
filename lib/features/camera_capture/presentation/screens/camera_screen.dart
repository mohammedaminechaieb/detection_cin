import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../viewmodels/camera_viewmodel.dart';
import '../widgets/camera_overlay.dart';
import '../../../document_detection/presentation/viewmodels/detection_viewmodel.dart';
import '../../../document_detection/domain/entities/detected_document.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _streamedController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cameraViewModel = context.read<CameraViewModel>();
      await cameraViewModel.initializeCamera();

      final controller = cameraViewModel.cameraController;
      if (controller != null && mounted) {
        final detectionViewModel = context.read<DetectionViewModel>();
        controller.startImageStream(detectionViewModel.onFrame);
        _streamedController = controller;
      }
    });
  }

  @override
  void dispose() {
    _streamedController?.stopImageStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<CameraViewModel>(
        builder: (context, viewModel, _) {
          if (viewModel.errorMessage != null) {
            return Center(
              child: Text(
                viewModel.errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            );
          }

          if (!viewModel.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          final controller = viewModel.cameraController as CameraController;

          return Center(
            child: AspectRatio(
              aspectRatio: 1 / controller.value.aspectRatio, 
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  Consumer<DetectionViewModel>(
                    builder: (context, detectionViewModel, _) {
                      return CameraOverlay(
                        side: detectionViewModel.currentSide,
                        isBorderDetected: detectionViewModel.isBorderDetected,
                        isFaceDetected: detectionViewModel.isFaceDetected,
                        isLogoDetected: detectionViewModel.isLogoDetected,
                        isFlagDetected: detectionViewModel.isFlagDetected,
                        isBarcodeDetected: detectionViewModel.isBarcodeDetected,
                        isFingerprintDetected: detectionViewModel.isFingerprintDetected,
                        isSeparationLineDetected: detectionViewModel.isSeparationLineDetected,
                      );
                    },
                  ),

                  
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Consumer<DetectionViewModel>(
                        builder: (context, detectionViewModel, _) {
                          final isFront = detectionViewModel.currentSide == CardSide.front;
                          return ElevatedButton(
                            onPressed: () {
                              detectionViewModel.setSide(
                                isFront ? CardSide.back : CardSide.front,
                              );
                            },
                            child: Text(
                              'Basculer vers ${isFront ? "verso" : "recto"}',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}