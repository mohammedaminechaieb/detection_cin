import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Améliore la lisibilité d'une image de carte déjà recadrée et orientée
/// (venant de `document_detection`) : léger boost de contraste + netteté.
/// Volontairement discret - l'objectif est la lisibilité du document
/// (texte, photo, code-barres), pas un rendu "artistique".
///
/// ASSOMPTION NON VÉRIFIÉE : API `package:image` v4.x (paramètres nommés -
/// `img.adjustColor(image, contrast: ..., brightness: ...)`,
/// `img.gaussianBlur(image, radius: ...)`). Si le projet est sur
/// `package:image` v3.x, ces appels utilisent des arguments positionnels -
/// à ajuster si `flutter analyze` le signale. Nécessite `image: ^4.x` dans
/// pubspec.yaml.
class CardImageEnhancer {
  const CardImageEnhancer({
    this.contrast = 1.15,
    this.brightness = 1.02,
    this.sharpenRadius = 2,
    this.sharpenAmount = 0.6,
  });

  final double contrast;
  final double brightness;
  final int sharpenRadius;
  final double sharpenAmount;

  Uint8List enhance(Uint8List pngBytes) {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) return pngBytes;

    final contrasted = img.adjustColor(decoded, contrast: contrast, brightness: brightness);
    final result = sharpenRadius > 0 ? _sharpen(contrasted) : contrasted;

    return Uint8List.fromList(img.encodePng(result));
  }

  /// Unsharp mask simple : original + (original - flou) * amount, par
  /// canal, clampé. `image.clone()` avant le flou pour ne pas modifier
  /// `original` en place.
  img.Image _sharpen(img.Image original) {
    final blurred = img.gaussianBlur(original.clone(), radius: sharpenRadius);
    final out = original.clone();

    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final o = original.getPixel(x, y);
        final b = blurred.getPixel(x, y);
        out.setPixelRgb(
          x,
          y,
          (o.r + (o.r - b.r) * sharpenAmount).clamp(0, 255).toInt(),
          (o.g + (o.g - b.g) * sharpenAmount).clamp(0, 255).toInt(),
          (o.b + (o.b - b.b) * sharpenAmount).clamp(0, 255).toInt(),
        );
      }
    }
    return out;
  }
}