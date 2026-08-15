import 'dart:typed_data';

import '../../data/datasources/print_page_composer.dart';

/// Compose la page à imprimer (A4, recto/verso empilés) à partir des
/// images déjà améliorées. Séparé de `EnhanceCapturedCard` (voir ce
/// fichier pour pourquoi) - c'est l'étape la plus coûteuse du
/// post-traitement, donc celle qu'on veut pouvoir lancer *après* avoir
/// déjà affiché le recto/verso amélioré, pas avant.
class ComposePrintPage {
  const ComposePrintPage({
    this._composer = const PrintPageComposer(),
  });

  final PrintPageComposer _composer;

  Uint8List call(Uint8List enhancedFrontPng, Uint8List enhancedBackPng) {
    return _composer.compose(enhancedFrontPng, enhancedBackPng);
  }
}