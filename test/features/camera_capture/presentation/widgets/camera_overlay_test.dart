import 'package:detection_cin/features/document_detection/domain/entities/detected_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/camera_capture/presentation/widgets/camera_overlay.dart';

void main() {
  testWidgets('CameraOverlay affiche un cadre avec le bon ratio', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CameraOverlay(side: CardSide.front, isBorderDetected: true )),
      ),
    );

    final aspectRatioFinder = find.byType(AspectRatio);
    expect(aspectRatioFinder, findsOneWidget);

    final aspectRatioWidget = tester.widget<AspectRatio>(aspectRatioFinder);
    expect(aspectRatioWidget.aspectRatio, closeTo(1.58, 0.01));

    // Vérifie que le conteneur avec bordure est bien présent
    expect(find.byType(Container), findsOneWidget);
  });
}
