import 'package:flutter/foundation.dart';

import '../../domain/entities/enhancement_settings.dart';
import '../../domain/entities/processed_card.dart';
import '../../domain/usecases/compose_print_page.dart';
import '../../domain/usecases/enhance_captured_card.dart';

/// Lance le post-traitement dès que les deux côtés sont capturés, en deux
/// étapes séparées, chacune dans son propre isolate via `compute()`:
///
/// 1. Amélioration du recto/verso (rapide) - publiée immédiatement une
///    fois prête, donc `ResultPreviewScreen` peut afficher les images
///    améliorées sans attendre la suite.
/// 2. Composition de la page à imprimer (plus lente - canevas A4 pleine
///    résolution, deux redimensionnements, deux compositions) - lancée
///    seulement après l'étape 1, et publiée séparément quand elle finit.
///
/// Avant, les deux étapes tournaient l'une après l'autre dans un seul
/// `compute()`, et `result` ne devenait non-null qu'une fois TOUT fini -
/// donc même le recto/verso amélioré restait invisible pendant toute la
/// composition de la page, qui est l'étape la plus lente. C'est ce qui
/// donnait l'impression que "la page à imprimer met du temps à
/// apparaître" alors qu'en réalité c'était tout l'écran de vérification
/// qui attendait sur elle.
class PostprocessingViewModel extends ChangeNotifier {
  ProcessedCard? _result;
  ProcessedCard? get result => _result;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  bool _isComposingPrintPage = false;
  bool get isComposingPrintPage => _isComposingPrintPage;

  String? _error;
  String? get error => _error;

  String? _printPageError;
  String? get printPageError => _printPageError;

  EnhancementSettings _settings = EnhancementSettings.defaults;
  EnhancementSettings get settings => _settings;

  Future<void> process(
    Uint8List frontPng,
    Uint8List backPng, {
    EnhancementSettings? settings,
  }) async {
    _settings = settings ?? _settings;
    _isProcessing = true;
    _error = null;
    _printPageError = null;
    notifyListeners();

    Uint8List enhancedFront;
    Uint8List enhancedBack;
    try {
      final enhanced = await compute(
        _enhanceInBackground,
        _EnhanceInput(frontPng, backPng, _settings),
      );
      enhancedFront = enhanced.$1;
      enhancedBack = enhanced.$2;
      _result = ProcessedCard(front: enhancedFront, back: enhancedBack);
    } catch (e) {
      _error = e.toString();
      _isProcessing = false;
      notifyListeners();
      return;
    }

    _isProcessing = false;
    notifyListeners();

    // Print-page composition starts right after enhancement finishes,
    // but is not awaited by `process()` itself - the caller (and the UI)
    // already has `result.front`/`result.back` to show at this point.
    _composePrintPage(enhancedFront, enhancedBack);
  }

  Future<void> _composePrintPage(Uint8List enhancedFront, Uint8List enhancedBack) async {
    _isComposingPrintPage = true;
    notifyListeners();

    try {
      final printPage = await compute(
        _composeInBackground,
        _ComposeInput(enhancedFront, enhancedBack),
      );
      _result = _result?.copyWith(printPage: printPage);
    } catch (e) {
      _printPageError = e.toString();
    } finally {
      _isComposingPrintPage = false;
      notifyListeners();
    }
  }

  /// À appeler quand l'utilisateur relance la capture (bouton "Reprendre"),
  /// pour ne pas garder un résultat périmé affiché.
  void reset() {
    _result = null;
    _error = null;
    _printPageError = null;
    _isProcessing = false;
    _isComposingPrintPage = false;
    _settings = EnhancementSettings.defaults;
    notifyListeners();
  }
}

class _EnhanceInput {
  const _EnhanceInput(this.frontPng, this.backPng, this.settings);
  final Uint8List frontPng;
  final Uint8List backPng;
  final EnhancementSettings settings;
}

class _ComposeInput {
  const _ComposeInput(this.enhancedFront, this.enhancedBack);
  final Uint8List enhancedFront;
  final Uint8List enhancedBack;
}

// Top-level functions required by `compute()` - must not capture any
// instance state, only pure input -> output.
(Uint8List, Uint8List) _enhanceInBackground(_EnhanceInput input) {
  const usecase = EnhanceCapturedCard();
  return usecase(input.frontPng, input.backPng, settings: input.settings);
}

Uint8List _composeInBackground(_ComposeInput input) {
  const usecase = ComposePrintPage();
  return usecase(input.enhancedFront, input.enhancedBack);
}