import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Améliore la lisibilité d'une image de carte déjà recadrée et orientée
/// (venant de `document_detection`) : léger boost de contraste + netteté,
/// et optionnellement un mode "scan" noir et blanc.
/// Volontairement discret - l'objectif est la lisibilité du document
/// (texte, photo, code-barres), pas un rendu "artistique".
///
/// ASSOMPTION NON VÉRIFIÉE : API `package:image` v4.x (paramètres nommés -
/// `img.adjustColor(image, contrast: ..., brightness: ...)`,
/// `img.gaussianBlur(image, radius: ...)`,
/// `img.convolution(image, filter: [...], div: ..., offset: ...)`,
/// `img.grayscale(image)`). Si le projet est sur `package:image` v3.x, ces
/// appels utilisent des arguments positionnels et `convolution` peut ne
/// pas exister sous ce nom - à ajuster si `flutter analyze` le signale.
/// Nécessite `image: ^4.x` dans pubspec.yaml. Pas de `pubspec.yaml` dans
/// ce qui m'a été fourni pour confirmer la version installée.
class CardImageEnhancer {
  const CardImageEnhancer({
    this.contrast = 1.15,
    this.brightness = 1.02,
    this.sharpenRadius = 2,
    this.sharpenAmount = 0.6,
    this.grayscale = false,
  });

  final double contrast;
  final double brightness;

  /// Only used as an on/off gate for sharpening (`sharpenRadius > 0` in
  /// [enhance]) - the fixed 3x3 kernel in [_sharpen] doesn't have a
  /// variable radius. Kept as a field rather than a bool to avoid
  /// changing this class's public constructor shape.
  final int sharpenRadius;
  final double sharpenAmount;

  /// "Scan" mode - converts to grayscale as the last step, after
  /// contrast/sharpen so those still operate on full color information
  /// (sharpening in particular benefits from more channel detail before
  /// being flattened to one channel).
  final bool grayscale;

  Uint8List enhance(Uint8List pngBytes) {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) return pngBytes;

    final contrasted = img.adjustColor(decoded, contrast: contrast, brightness: brightness);
    final sharpened = sharpenRadius > 0 ? _sharpen(contrasted) : contrasted;
    final result = grayscale ? img.grayscale(sharpened) : sharpened;

    return Uint8List.fromList(img.encodePng(result));
  }

  /// Unsharp mask via a single 3x3 convolution kernel, run natively by
  /// `img.convolution` instead of a manual per-pixel getPixel/setPixelRgb
  /// loop (which was slow enough to need shunting onto a `compute()`
  /// isolate just for this one step - see `PostprocessingViewModel`).
  ///
  /// The kernel is the standard sharpen form `identity + amount *
  /// (identity - blur)`, approximated directly as a kernel rather than
  /// doing a separate blur pass + per-pixel combine:
  ///   center   = 1 + 4 * amount
  ///   4-neighbors (up/down/left/right) = -amount
  /// which is a discrete Laplacian-based sharpen scaled by [sharpenAmount].
  /// `sharpenRadius` is intentionally unused by this 3x3-kernel approach;
  /// see note on the field below.
  img.Image _sharpen(img.Image original) {
    final a = sharpenAmount;
    final kernel = <double>[
      0, -a, 0,
      -a, 1 + 4 * a, -a,
      0, -a, 0,
    ];
    return img.convolution(original.clone(), filter: kernel);
  }
}