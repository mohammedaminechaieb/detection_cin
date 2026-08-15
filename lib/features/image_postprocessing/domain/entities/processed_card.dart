import 'dart:typed_data';

/// Sortie du post-traitement : le recto/verso amélioré (contraste +
/// netteté), et la page composée prête à l'impression - `printPage` est
/// `null` tant que la composition (l'étape la plus coûteuse) n'est pas
/// encore terminée, pour que `PostprocessingViewModel` puisse publier le
/// recto/verso dès qu'il est prêt sans attendre la page complète.
class ProcessedCard {
  const ProcessedCard({
    required this.front,
    required this.back,
    this.printPage,
  });

  final Uint8List front;
  final Uint8List back;
  final Uint8List? printPage;

  ProcessedCard copyWith({Uint8List? printPage}) => ProcessedCard(
        front: front,
        back: back,
        printPage: printPage ?? this.printPage,
      );
}