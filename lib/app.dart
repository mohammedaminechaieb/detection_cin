import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'core/services/camera_service.dart';
import 'core/services/cascade_asset_loader.dart';
import 'features/camera_capture/presentation/viewmodels/camera_viewmodel.dart';
import 'features/camera_capture/presentation/screens/camera_screen.dart';
import 'features/document_detection/data/datasources/document_detection_datasource.dart';
import 'features/document_detection/data/repositories/detection_repository_impl.dart';
import 'features/document_detection/presentation/viewmodels/detection_viewmodel.dart';
import 'features/autocapture/presentation/viewmodels/autocapture_viewmodel.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  DetectionViewModel? _detectionViewModel;
  AutocaptureViewModel? _autocaptureViewModel;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // Charge le cascade + les templates une seule fois au demarrage, avant
  // d'assembler la chaine de detection -- deplace ici depuis main.dart pour
  // que main.dart reste minimal (juste runApp).
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

    final viewModel = DetectionViewModel(
      detectionRepository,
      autocaptureViewModel: autocaptureViewModel,
    );
    viewModel.loadTemplates(
      logoBytes: logoData.buffer.asUint8List(),
      flagBytes: flagData.buffer.asUint8List(),
    );

    if (!mounted) return;
    setState(() {
      _detectionViewModel = viewModel;
      _autocaptureViewModel = autocaptureViewModel;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ecran de chargement le temps que le cascade + les templates soient prets
    if (_detectionViewModel == null || _autocaptureViewModel == null) {
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