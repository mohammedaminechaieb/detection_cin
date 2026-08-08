import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Contrôle de netteté ("is this frame sharp enough to capture"),
/// basé sur la variance du Laplacien : une image floue a des
/// contours lissés donc une variance faible, une image nette a des
/// contours marqués partout donc une variance élevée. Même famille
/// de technique que `FingerprintPresenceDetector` (déjà basé sur un
/// Laplacien) - rien de nouveau côté dépendances.
///
/// NOTE : écrit sans SDK Dart/Flutter disponible dans cet
/// environnement (même contrainte que le reste du repo jusqu'ici).
/// Les appels opencv_dart ci-dessous (`cv.laplacian`, `cv.meanStdDev`,
/// signature de retour en record) correspondent à l'API telle que je
/// la connais, mais vérifie contre la version épinglée dans
/// `pubspec.yaml` au premier `flutter pub get` / `flutter analyze` -
/// c'est le genre de détail qui bouge d'une version à l'autre.
class BlurDetector {
  const BlurDetector();

  /// Sous ce score, la frame est considérée trop floue pour être
  /// capturée. Valeur de départ arbitraire - à recalibrer avec
  /// quelques captures réelles nettes vs floues sur device, comme les
  /// autres seuils du projet.
  static const double kMinSharpnessScore = 120.0;

  /// Score de netteté de [mat] (plus haut = plus net). [mat] peut
  /// être couleur ou déjà en niveaux de gris, plein cadre ou une ROI
  /// (ex. la carte redressée) - selon où tu veux appliquer le check.
  double sharpnessScore(cv.Mat mat) {
    final isGray = mat.channels == 1;
    final gray = isGray ? mat : cv.cvtColor(mat, cv.COLOR_BGR2GRAY);

    final laplacian = cv.laplacian(gray, cv.MatType.CV_64F);
    // meanStdDev returns a (Scalar mean, Scalar stddev) record - it does
    // NOT take output-parameter Mats (that was an older API version).
    final (_, stddevScalar) = cv.meanStdDev(laplacian);
    final double sigma = stddevScalar.val1;

    laplacian.dispose();
    if (!isGray) gray.dispose();

    return sigma * sigma;
  }

  bool isSharpEnough(cv.Mat mat) => sharpnessScore(mat) >= kMinSharpnessScore;
}