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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cascadePath = await loadCascadeAssetPath();
    final logoData = await rootBundle.load('assets/templates/logo.png');
    final flagData = await rootBundle.load('assets/templates/flag.png');

    final detectionDatasource = DocumentDetectionDataSource(cascadePath);
    final detectionRepository = DetectionRepositoryImpl(detectionDatasource);

    final autocaptureViewModel = AutocaptureViewModel(
      onCaptureReady: () {
        // TODO next step: actually grab/save the still frame
      },
    );

    final capturedCardsViewModel = CapturedCardsViewModel();
    final postprocessingViewModel = PostprocessingViewModel();

    final viewModel = DetectionViewModel(
      detectionRepository,
      autocaptureViewModel: autocaptureViewModel,
    );
    viewModel.loadTemplates(
      logoBytes: logoData.buffer.asUint8List(),
      flagBytes: flagData.buffer.asUint8List(),
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
  }

  @override
  Widget build(BuildContext context) {
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