import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../domain/entities/enhancement_settings.dart';
import '../../domain/entities/processed_card.dart';
import '../../domain/usecases/process_captured_card.dart';

/// Lance le post-traitement (amélioration + composition de la page à
/// imprimer) dès que les deux côtés sont capturés, dans un isolate séparé
/// via `compute()` - le décodage/encodage PNG et la composition de la
/// page à imprimer restent un travail non-trivial sur une image de
/// carte pleine résolution, donc on garde ça hors du thread UI même si
/// `CardImageEnhancer` n'utilise plus de boucle pixel par pixel pour le
/// sharpen (voir `CardImageEnhancer._sharpen`, maintenant `img.convolution`).
class PostprocessingViewModel extends ChangeNotifier {
  ProcessedCard? _result;
  ProcessedCard? get result => _result;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  String? _error;
  String? get error => _error;

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
    notifyListeners();

    try {
      _result = await compute(
        _processInBackground,
        _ProcessInput(frontPng, backPng, _settings),
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// À appeler quand l'utilisateur relance la capture (bouton "Reprendre"),
  /// pour ne pas garder un résultat périmé affiché.
  void reset() {
    _result = null;
    _error = null;
    _isProcessing = false;
    _settings = EnhancementSettings.defaults;
    notifyListeners();
  }
}

class _ProcessInput {
  const _ProcessInput(this.frontPng, this.backPng, this.settings);
  final Uint8List frontPng;
  final Uint8List backPng;
  final EnhancementSettings settings;
}

// Top-level function required by `compute()` - must not capture any
// instance state, only pure input -> output.
ProcessedCard _processInBackground(_ProcessInput input) {
  const usecase = ProcessCapturedCard();
  return usecase(input.frontPng, input.backPng, settings: input.settings);
}