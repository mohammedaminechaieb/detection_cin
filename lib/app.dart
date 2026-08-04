import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/camera_service.dart';
import 'features/camera_capture/presentation/viewmodels/camera_viewmodel.dart';
import 'features/camera_capture/presentation/screens/camera_screen.dart';
import 'features/document_detection/data/datasources/document_detection_datasource.dart';
import 'features/document_detection/data/repositories/detection_repository_impl.dart';
import 'features/document_detection/presentation/viewmodels/detection_viewmodel.dart';

class MyApp extends StatelessWidget {
  final String cascadePath;
  final Uint8List logoBytes;
  final Uint8List flagBytes;

  const MyApp({
    super.key,
    required this.cascadePath,
    required this.logoBytes,
    required this.flagBytes,
  });

  @override
  Widget build(BuildContext context) {
    // Composition root : on assemble la chaîne complète une seule fois ici
    final detectionDatasource = DocumentDetectionDataSource(cascadePath);
    final detectionRepository = DetectionRepositoryImpl(detectionDatasource);

    final detectionViewModel = DetectionViewModel(detectionRepository);
    detectionViewModel.loadTemplates(logoBytes: logoBytes, flagBytes: flagBytes);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CameraViewModel(CameraService()),
        ),
        ChangeNotifierProvider(
          create: (_) => detectionViewModel,
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