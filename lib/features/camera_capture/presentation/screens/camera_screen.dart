import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../viewmodels/camera_viewmodel.dart';
import '../widgets/camera_overlay.dart';
import '../../../document_detection/presentation/viewmodels/detection_viewmodel.dart';
import '../../../autocapture/presentation/viewmodels/autocapture_viewmodel.dart';
import '../../../document_detection/domain/entities/detected_document.dart';
import '../../../autocapture/domain/entities/capture_state.dart';
import '../../../result_preview/presentation/viewmodels/captured_cards_viewmodel.dart';
import '../../../result_preview/presentation/screens/result_preview_screen.dart';
import '../../../image_postprocessing/presentation/viewmodels/postprocessing_viewmodel.dart';

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
        if (kDebugMode) {
          detectionViewModel.onFrameDuration = (elapsed) {
            debugPrint('[detection] frame processed in ${elapsed.inMilliseconds}ms');
          };
        }
        controller.startImageStream(detectionViewModel.onFrame);
        _streamedController = controller;
      }
    });
    context.read<CapturedCardsViewModel>().addListener(_maybeShowPreview);
  }

  @override
  void dispose() {
    _streamedController?.stopImageStream();
    context.read<CapturedCardsViewModel>().removeListener(_maybeShowPreview);
    super.dispose();
  }

  void _maybeShowPreview() {
    final capturedCardsViewModel = context.read<CapturedCardsViewModel>();
    if (!capturedCardsViewModel.isComplete) return;
    if (!mounted || Navigator.of(context).canPop()) return;

    final card = capturedCardsViewModel.card;
    if (card.front == null || card.back == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultPreviewScreen(
          onRetake: () {
            capturedCardsViewModel.reset();
            context.read<PostprocessingViewModel>().reset();
            context.read<AutocaptureViewModel>().reset();
            context.read<DetectionViewModel>().setSide(CardSide.front);
            Navigator.of(context).pop();
          },
          onConfirm: () {
            // TODO next step: persist/upload the validated capture.
            Navigator.of(context).pop();
          },
        ),
      ),
    );
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
                    top: 40,
                    left: 0,
                    right: 0,
                    child: Consumer<AutocaptureViewModel>(
                      builder: (context, autocaptureViewModel, _) {
                        return _AutocaptureStatusBanner(
                          state: autocaptureViewModel.state,
                          issues: autocaptureViewModel.issues,
                          holdProgress: autocaptureViewModel.holdProgress,
                        );
                      },
                    ),
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

class _AutocaptureStatusBanner extends StatelessWidget {
  final CaptureState state;
  final QualityIssues issues;
  final double holdProgress;

  const _AutocaptureStatusBanner({
    required this.state,
    required this.issues,
    required this.holdProgress,
  });

  String get _label {
    switch (state) {
      case CaptureState.searching:
        return 'Placez la carte dans le cadre';
      case CaptureState.poorQuality:
        if (issues.tooBlurry) return 'Image floue';
        if (issues.tooDark) return 'Trop sombre';
        if (issues.tooBright) return 'Trop lumineux';
        if (issues.unstable) return 'Tenez stable';
        if (issues.contentMismatch) return 'Élément non détecté';
        return 'Ajustez la position';
      case CaptureState.holding:
        return 'Ne bougez plus...';
      case CaptureState.triggerCapture:
      case CaptureState.captured:
        return 'Capturé !';
    }
  }

  Color get _color {
    switch (state) {
      case CaptureState.holding:
      case CaptureState.triggerCapture:
      case CaptureState.captured:
        return Colors.green;
      case CaptureState.poorQuality:
        return Colors.red;
      case CaptureState.searching:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _color, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: TextStyle(color: _color, fontWeight: FontWeight.w600),
            ),
            if (state == CaptureState.holding) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  value: holdProgress,
                  color: Colors.green,
                  backgroundColor: Colors.white24,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}