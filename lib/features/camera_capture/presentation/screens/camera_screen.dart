import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
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
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/components/app_state_view.dart';
import '../../../capture_history/presentation/screens/capture_history_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  @override
  void initState() {
    super.initState();
    _initCamera();
    context.read<CapturedCardsViewModel>().addListener(_maybeShowPreview);
  }

  Future<void> _initCamera() async {
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
    }
  }

  @override
  void dispose() {
    // Deliberately does NOT call `_streamedController?.stopImageStream()`
    // here anymore - that used to race independently against
    // `CameraViewModel.dispose()` -> `CameraService.dispose()` disposing
    // the controller, with no guaranteed ordering between the two. Now
    // `CameraService.dispose()` stops the stream and awaits that before
    // disposing the controller itself, so there's a single place that
    // ordering is enforced instead of two independent call sites racing.
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
      PageRouteBuilder(
        transitionDuration: AppDurations.screenTransition,
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: ResultPreviewScreen(
            onRetake: () {
              capturedCardsViewModel.reset();
              context.read<PostprocessingViewModel>().reset();
              context.read<AutocaptureViewModel>().reset();
              context.read<DetectionViewModel>().setSide(CardSide.front);
              Navigator.of(context).pop();
            },
            onConfirmed: () {
              capturedCardsViewModel.reset();
              context.read<PostprocessingViewModel>().reset();
              context.read<AutocaptureViewModel>().reset();
              context.read<DetectionViewModel>().setSide(CardSide.front);
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<CameraViewModel>(
        builder: (context, viewModel, _) {
          if (viewModel.setupError == CameraSetupError.permissionDenied) {
            return AppStateView(
              icon: Icons.no_photography_outlined,
              title: 'Accès à la caméra requis',
              message:
                  'CIN Autocapture a besoin de la caméra pour scanner votre carte. '
                  'Autorisez l\'accès dans les réglages pour continuer.',
              actionLabel: 'Ouvrir les réglages',
              onAction: openAppSettings,
            );
          }

          if (viewModel.setupError == CameraSetupError.noCameraAvailable) {
            return const AppStateView(
              icon: Icons.videocam_off_outlined,
              title: 'Aucune caméra disponible',
              message: 'Cet appareil ne semble pas avoir de caméra utilisable.',
            );
          }

          if (viewModel.setupError == CameraSetupError.unknown) {
            return AppStateView(
              icon: Icons.error_outline,
              title: 'Impossible de démarrer la caméra',
              message: viewModel.errorMessage,
              actionLabel: 'Réessayer',
              onAction: _initCamera,
            );
          }

          if (!viewModel.isInitialized) {
            return const AppStateView(
              icon: Icons.camera_alt_outlined,
              title: 'Ouverture de la caméra...',
              iconColor: AppColors.accent,
            );
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

                  // Side chip + status banner share one top band, laid out
                  // in a Row rather than as two independently-centered
                  // Positioned widgets pinned to the same `top` value.
                  // Two independent widgets both claiming the horizontal
                  // center/left of the full screen width can visually
                  // collide once the banner's text gets long enough (e.g.
                  // "Trop lumineux, évitez les reflets") - a Row instead
                  // reserves real space for the chip so the banner is
                  // physically laid out to its right, never on top of it.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Consumer<DetectionViewModel>(
                              builder: (context, detectionViewModel, _) {
                                return _SideChip(side: detectionViewModel.currentSide);
                              },
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Center(
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
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _HistoryButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const CaptureHistoryScreen()),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: AppSpacing.lg,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      top: false,
                      child: Center(
                        child: Consumer<DetectionViewModel>(
                          builder: (context, detectionViewModel, _) {
                            final isFront = detectionViewModel.currentSide == CardSide.front;
                            return _SideToggleButton(
                              label: 'Basculer vers ${isFront ? "verso" : "recto"}',
                              onPressed: () {
                                detectionViewModel.setSide(isFront ? CardSide.back : CardSide.front);
                              },
                            );
                          },
                        ),
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

class _SideChip extends StatelessWidget {
  const _SideChip({required this.side});

  final CardSide side;

  @override
  Widget build(BuildContext context) {
    // No SafeArea here - the parent Positioned/SafeArea in CameraScreen's
    // build already insets the whole top band, wrapping again here was
    // harmless but redundant.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        side == CardSide.front ? 'RECTO' : 'VERSO',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: Icon(Icons.history, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _SideToggleButton extends StatelessWidget {
  const _SideToggleButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flip_camera_android_outlined, color: Colors.white, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
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
        if (issues.tooBlurry) return 'Image floue - tenez l\'appareil stable';
        if (issues.tooDark) return 'Trop sombre';
        if (issues.tooBright) return 'Trop lumineux, évitez les reflets';
        if (issues.unstable) return 'Ne bougez plus...';
        if (issues.contentMismatch) return 'Recentrez la carte';
        return 'Ajustez la position';
      case CaptureState.holding:
        return 'Ne bougez plus...';
      case CaptureState.triggerCapture:
      case CaptureState.captured:
        return 'Capturé !';
    }
  }

  IconData get _icon {
    switch (state) {
      case CaptureState.holding:
      case CaptureState.triggerCapture:
      case CaptureState.captured:
        return Icons.check_circle_outline;
      case CaptureState.poorQuality:
        if (issues.tooBlurry) return Icons.blur_on;
        if (issues.tooDark) return Icons.brightness_low;
        if (issues.tooBright) return Icons.brightness_high;
        return Icons.warning_amber_rounded;
      case CaptureState.searching:
        return Icons.crop_free;
    }
  }

  Color get _color {
    switch (state) {
      case CaptureState.holding:
      case CaptureState.triggerCapture:
      case CaptureState.captured:
        return AppColors.success;
      case CaptureState.poorQuality:
        return AppColors.danger;
      case CaptureState.searching:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: AppDurations.normal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: _color, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(_icon, color: _color, size: 18),
                const SizedBox(width: AppSpacing.sm),
                // `Flexible` (not a bare `Text`) is the actual fix for the
                // "hits the edge of the screen" overflow: this banner sits
                // inside an `Expanded` slot (see CameraScreen.build) whose
                // width is a *tight* upper bound - it's whatever's left of
                // the screen after the side chip. `Row`'s `mainAxisSize.min`
                // only controls how the Row itself sizes within that bound,
                // it does nothing to stop a long, unwrapped `Text` (e.g.
                // "Trop lumineux, évitez les reflets") from demanding more
                // width than that bound allows - and when a child asks for
                // more than its parent's max width, Flutter throws "A
                // RenderFlex overflowed by N pixels" and paints the
                // black/yellow hazard stripes right at that edge. Wrapping
                // the Text in `Flexible` lets it shrink to the space that's
                // actually available and wrap/ellipsize instead of
                // overflowing past it.
                Flexible(
                  child: Text(
                    _label,
                    style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 13),
                    textAlign: TextAlign.left,
                    softWrap: true,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (state == CaptureState.holding) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: holdProgress,
                    color: AppColors.success,
                    backgroundColor: Colors.white24,
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}