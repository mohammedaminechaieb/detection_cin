import 'dart:typed_data';

import '../../data/datasources/card_image_enhancer.dart';
import '../entities/enhancement_settings.dart';

/// Améliore le recto et le verso individuellement (contraste + netteté +
/// N&B optionnel). Séparé de la composition de la page à imprimer (voir
/// `ComposePrintPage`) pour que `PostprocessingViewModel` puisse afficher
/// le recto/verso amélioré dès qu'il est prêt, sans attendre la
/// composition de la page - qui est le poste le plus coûteux (allocation
/// d'un canevas A4 pleine résolution + deux redimensionnements + deux
/// compositions), donc celui qui bénéficie le plus à ne pas bloquer le
/// reste. Pas de dépendance caméra/OpenCV - ne touche que des bytes PNG
/// déjà recadrés et orientés (fournis par `document_detection`). Conçu
/// pour tourner dans un isolate via `compute()`, donc volontairement sans
/// état et sans dépendance Flutter.
class EnhanceCapturedCard {
  const EnhanceCapturedCard();

  (Uint8List front, Uint8List back) call(
    Uint8List frontPng,
    Uint8List backPng, {
    EnhancementSettings settings = EnhancementSettings.defaults,
  }) {
    final enhancer = CardImageEnhancer(
      contrast: settings.contrastLevel.factor,
      sharpenRadius: settings.sharpenEnabled ? 2 : 0,
      grayscale: settings.grayscale,
    );

    return (enhancer.enhance(frontPng), enhancer.enhance(backPng));
  }
}