import 'package:flutter/foundation.dart';

import '../../../document_detection/domain/entities/detected_document.dart' show CardSide;
import '../../domain/entities/captured_card.dart';

/// Garde les images capturées du recto et du verso, une fois que
/// `AutocaptureViewModel` a validé chaque côté. Alimenté par
/// `DetectionViewModel.onCardCaptured`, consommé par
/// `ResultPreviewScreen`.
class CapturedCardsViewModel extends ChangeNotifier {
  CapturedCard _card = const CapturedCard();
  CapturedCard get card => _card;

  bool get isComplete => _card.isComplete;

  void setCapture(CardSide side, Uint8List pngBytes) {
    _card = side == CardSide.front
        ? _card.copyWith(front: pngBytes)
        : _card.copyWith(back: pngBytes);
    notifyListeners();
  }

  /// À appeler quand l'utilisateur relance la capture (bouton
  /// "Reprendre" côté preview), pour repartir sur un cycle propre.
  void reset() {
    _card = const CapturedCard();
    notifyListeners();
  }
}