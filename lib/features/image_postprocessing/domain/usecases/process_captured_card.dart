import 'dart:typed_data';

import '../../data/datasources/card_image_enhancer.dart';
import '../../data/datasources/print_page_composer.dart';
import '../entities/enhancement_settings.dart';
import '../entities/processed_card.dart';

/// Orchestration pure : améliore le recto et le verso individuellement,
/// puis compose la page à imprimer à partir des versions améliorées.
/// Pas de dépendance caméra/OpenCV - ne touche que des bytes PNG déjà
/// recadrés et orientés (fournis par `document_detection`). Conçu pour
/// tourner dans un isolate via `compute()` (voir `PostprocessingViewModel`),
/// donc volontairement sans état et sans dépendance Flutter.
class ProcessCapturedCard {
  const ProcessCapturedCard({
    PrintPageComposer composer = const PrintPageComposer(),
  }) : _composer = composer;

  final PrintPageComposer _composer;

  ProcessedCard call(
    Uint8List frontPng,
    Uint8List backPng, {
    EnhancementSettings settings = EnhancementSettings.defaults,
  }) {
    final enhancer = CardImageEnhancer(
      contrast: settings.contrastLevel.factor,
      sharpenRadius: settings.sharpenEnabled ? 2 : 0,
      grayscale: settings.grayscale,
    );

    final enhancedFront = enhancer.enhance(frontPng);
    final enhancedBack = enhancer.enhance(backPng);
    final printPage = _composer.compose(enhancedFront, enhancedBack);

    return ProcessedCard(
      front: enhancedFront,
      back: enhancedBack,
      printPage: printPage,
    );
  }
}