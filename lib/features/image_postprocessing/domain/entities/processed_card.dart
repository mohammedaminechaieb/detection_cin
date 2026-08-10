import 'dart:typed_data';

/// Sortie finale du post-traitement : les images recto/verso améliorées
/// (contraste + netteté), et la page composée prête à l'impression.
class ProcessedCard {
  const ProcessedCard({
    required this.front,
    required this.back,
    required this.printPage,
  });

  final Uint8List front;
  final Uint8List back;
  final Uint8List printPage;
}