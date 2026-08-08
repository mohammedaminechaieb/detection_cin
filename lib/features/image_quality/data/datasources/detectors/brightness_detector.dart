import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Statut de luminosité d'une frame par rapport aux bornes acceptables.
enum BrightnessStatus { tooDark, ok, tooBright }

/// Contrôle de luminosité, basé sur l'intensité moyenne en niveaux de
/// gris. Volontairement simple (une moyenne globale) pour ce jalon -
/// une version future pourrait regarder l'histogramme pour détecter
/// des reflets localisés (plastification de la CIN), mais ce n'est
/// pas dans le scope de l'étape 3.
///
/// Même remarque que `BlurDetector` : signatures opencv_dart à
/// vérifier contre la version installée (`cv.mean` en particulier
/// peut retourner un `Scalar` avec une API légèrement différente
/// selon la version du package).
class BrightnessDetector {
  const BrightnessDetector();

  static const double kMinMeanBrightness = 60.0;
  static const double kMaxMeanBrightness = 205.0;

  /// Intensité moyenne (0-255) de [mat].
  double meanBrightness(cv.Mat mat) {
    final isGray = mat.channels == 1;
    final gray = isGray ? mat : cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    final scalar = cv.mean(gray);
    if (!isGray) gray.dispose();
    return scalar.val1;
  }

  BrightnessStatus classify(cv.Mat mat) {
    final brightness = meanBrightness(mat);
    if (brightness < kMinMeanBrightness) return BrightnessStatus.tooDark;
    if (brightness > kMaxMeanBrightness) return BrightnessStatus.tooBright;
    return BrightnessStatus.ok;
  }
}
