import 'dart:typed_data';

/// Résultat final de la capture : les images (PNG) du recto et du verso
/// de la carte, telles que produites par `DetectionViewModel` au moment
/// où `AutocaptureViewModel` valide chaque côté.
class CapturedCard {
  const CapturedCard({this.front, this.back});

  final Uint8List? front;
  final Uint8List? back;

  bool get isComplete => front != null && back != null;

  CapturedCard copyWith({Uint8List? front, Uint8List? back}) => CapturedCard(
        front: front ?? this.front,
        back: back ?? this.back,
      );
}