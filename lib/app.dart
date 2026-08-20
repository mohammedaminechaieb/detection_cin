import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'core/services/camera_service.dart';
import 'core/services/cascade_asset_loader.dart';
import 'features/camera_capture/presentation/viewmodels/camera_viewmodel.dart';
import 'features/camera_capture/presentation/screens/camera_screen.dart';
import 'features/document_detection/data/datasources/document_detection_datasource.dart';
import 'features/document_detection/data/repositories/detection_repository_impl.dart';
import 'features/document_detection/domain/entities/detected_document.dart' show CardSide;
import 'features/document_detection/presentation/viewmodels/detection_viewmodel.dart';
import 'features/autocapture/presentation/viewmodels/autocapture_viewmodel.dart';
import 'features/result_preview/presentation/viewmodels/captured_cards_viewmodel.dart';
import 'features/image_postprocessing/presentation/viewmodels/postprocessing_viewmodel.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  DetectionViewModel? _detectionViewModel;
  AutocaptureViewModel? _autocaptureViewModel;
  CapturedCardsViewModel? _capturedCardsViewModel;
  PostprocessingViewModel? _postprocessingViewModel;

  /// Set if `_bootstrap` fails - most notably if the detection isolate
  /// worker fails to initialize (bad cascade path, corrupt template
  /// asset, etc.). Previously an init failure here left the worker
  /// silently reporting itself ready anyway (see `DetectionIsolateWorker.
  /// spawn`'s fix), so the app proceeded straight into a camera screen
  /// that would throw on every single frame. Now that `initialize()`
  /// actually throws on failure, this needs to be caught and shown as a
  /// legible startup error instead of leaving `build` stuck on its
  /// loading spinner forever (or letting the exception surface as an
  /// unhandled crash).
  Object? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final cascadePath = await loadCascadeAssetPath();
      final logoData = await rootBundle.load('assets/templates/logo.png');
      final flagData = await rootBundle.load('assets/templates/flag.png');
      final logoBytes = logoData.buffer.asUint8List();
      final flagBytes = flagData.buffer.asUint8List();

      // Still constructed on the main isolate, even though live frame
      // analysis now happens inside `DetectionIsolateWorker` (a separate
      // background isolate with its own copy of this same pipeline) - this
      // instance is only used for the occasional, user-triggered recrop
      // (see `RecropScreen`/`ResultPreviewScreen`), which is infrequent and
      // cheap enough that running it here doesn't reintroduce the lag.
      final detectionDatasource = DocumentDetectionDataSource(cascadePath);
      final detectionRepository = DetectionRepositoryImpl(detectionDatasource);

      final autocaptureViewModel = AutocaptureViewModel(
        onCaptureReady: () {
          // Grabbing/saving the still frame itself happens in
          // DetectionViewModel.onFrame (the `justCaptured` check, once
          // `autocaptureViewModel.state` flips to CaptureState.captured) -
          // this callback only needs to exist as the state-machine signal
          // AutocaptureViewModel fires; nothing else to do here.
        },
      );

      final capturedCardsViewModel = CapturedCardsViewModel();
      final postprocessingViewModel = PostprocessingViewModel();

      final viewModel = DetectionViewModel(
        detectionRepository,
        autocaptureViewModel: autocaptureViewModel,
      );
      // Spawns the background isolate and loads the cascade + templates
      // into it - must be awaited before the camera stream starts feeding
      // it frames (CameraScreen only calls startImageStream once this
      // whole bootstrap has finished and the provider is available). Can
      // now throw (see `DetectionIsolateWorker.spawn`) if that init fails,
      // which the try/catch around this whole method turns into
      // `_bootstrapError` instead of an unhandled exception.
      await viewModel.initialize(
        cascadePath: cascadePath,
        logoBytes: logoBytes,
        flagBytes: flagBytes,
      );

      // When a side is captured: store its bytes, then either advance to the
      // back (front just captured) or kick off postprocessing (back just
      // captured - CameraScreen picks up `capturedCardsViewModel.isComplete`
      // and shows the preview screen, which reads `postprocessingViewModel`
      // for the enhanced images + print page once ready).
      viewModel.onCardCaptured = (bytes, side) {
        capturedCardsViewModel.setCapture(side, bytes);
        if (side == CardSide.front) {
          autocaptureViewModel.reset();
          viewModel.setSide(CardSide.back);
        } else {
          final card = capturedCardsViewModel.card;
          postprocessingViewModel.process(card.front!, bytes);
        }
      };

      if (!mounted) return;
      setState(() {
        _detectionViewModel = viewModel;
        _autocaptureViewModel = autocaptureViewModel;
        _capturedCardsViewModel = capturedCardsViewModel;
        _postprocessingViewModel = postprocessingViewModel;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _bootstrapError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Impossible de démarrer la détection de carte.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_bootstrapError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() => _bootstrapError = null);
                      _bootstrap();
                    },
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_detectionViewModel == null ||
        _autocaptureViewModel == null ||
        _capturedCardsViewModel == null ||
        _postprocessingViewModel == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CameraViewModel(CameraService()),
        ),
        ChangeNotifierProvider.value(
          value: _detectionViewModel!,
        ),
        ChangeNotifierProvider.value(
          value: _autocaptureViewModel!,
        ),
        ChangeNotifierProvider.value(
          value: _capturedCardsViewModel!,
        ),
        ChangeNotifierProvider.value(
          value: _postprocessingViewModel!,
        ),
      ],
      child: MaterialApp(
        title: 'CIN Autocapture',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
        ),
        home: const CameraScreen(),
      ),
    );
  }
}