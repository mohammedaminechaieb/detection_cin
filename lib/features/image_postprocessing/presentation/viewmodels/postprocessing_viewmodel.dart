import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../domain/entities/processed_card.dart';
import '../../domain/usecases/process_captured_card.dart';

/// Lance le post-traitement (amélioration + composition de la page à
/// imprimer) dès que les deux côtés sont capturés, dans un isolate séparé
/// via `compute()` - la boucle unsharp-mask pixel par pixel dans
/// `CardImageEnhancer` peut prendre quelques centaines de ms sur une
/// image de carte, on ne veut pas bloquer l'UI pendant ce temps.
class PostprocessingViewModel extends ChangeNotifier {
  ProcessedCard? _result;
  ProcessedCard? get result => _result;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  String? _error;
  String? get error => _error;

  Future<void> process(Uint8List frontPng, Uint8List backPng) async {
    _isProcessing = true;
    _error = null;
    notifyListeners();

    try {
      _result = await compute(_processInBackground, _ProcessInput(frontPng, backPng));
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
    notifyListeners();
  }
}

class _ProcessInput {
  const _ProcessInput(this.frontPng, this.backPng);
  final Uint8List frontPng;
  final Uint8List backPng;
}

// Top-level function required by `compute()` - must not capture any
// instance state, only pure input -> output.
ProcessedCard _processInBackground(_ProcessInput input) {
  const usecase = ProcessCapturedCard();
  return usecase(input.frontPng, input.backPng);
}