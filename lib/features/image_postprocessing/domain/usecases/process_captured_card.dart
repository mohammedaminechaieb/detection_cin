import 'dart:typed_data';

import '../../data/datasources/card_image_enhancer.dart';
import '../../data/datasources/print_page_composer.dart';
import '../entities/processed_card.dart';

/// Orchestration pure : améliore le recto et le verso individuellement,
/// puis compose la page à imprimer à partir des versions améliorées.
/// Pas de dépendance caméra/OpenCV - ne touche que des bytes PNG déjà
/// recadrés et orientés (fournis par `document_detection`). Conçu pour
/// tourner dans un isolate via `compute()` (voir `PostprocessingViewModel`),
/// donc volontairement sans état et sans dépendance Flutter.
class ProcessCapturedCard {
  const ProcessCapturedCard({
    CardImageEnhancer enhancer = const CardImageEnhancer(),
    PrintPageComposer composer = const PrintPageComposer(),
  })  : _enhancer = enhancer,
        _composer = composer;

  final CardImageEnhancer _enhancer;
  final PrintPageComposer _composer;

  ProcessedCard call(Uint8List frontPng, Uint8List backPng) {
    final enhancedFront = _enhancer.enhance(frontPng);
    final enhancedBack = _enhancer.enhance(backPng);
    final printPage = _composer.compose(enhancedFront, enhancedBack);

    return ProcessedCard(
      front: enhancedFront,
      back: enhancedBack,
      printPage: printPage,
    );
  }
}