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
  /// autres seuils du projet. Recalibrer en particulier après le fix
  /// CLAHE ci-dessous : le score n'est plus sur la même échelle qu'avant
  /// (CLAHE renforce le contraste local donc la variance du Laplacien
  /// avant ce fix), donc une valeur qui semblait correcte sur d'anciennes
  /// captures ne l'est plus forcément.
  static const double kMinSharpnessScore = 120.0;

  /// Score de netteté de [mat] (plus haut = plus net). [mat] peut
  /// être couleur ou déjà en niveaux de gris, plein cadre ou une ROI
  /// (ex. la carte redressée) - selon où tu veux appliquer le check.
  double sharpnessScore(cv.Mat mat) {
    final isGray = mat.channels == 1;
    final gray = isGray ? mat : cv.cvtColor(mat, cv.COLOR_BGR2GRAY);

    // CLAHE before the Laplacian - this is the actual fix for "floue"
    // (blurry) being reported almost always on a very light surface, even
    // on frames that were genuinely in focus. A light-on-light scene
    // (light card, light background/surface) has real edges that only
    // ever differ by a couple of gray levels of *local* contrast - same
    // root cause as `DocumentContourDetector`'s light-on-light problem
    // (see that file's `_preprocessGray`/`_preprocessGrayFast`), just
    // showing up here as a sharpness check instead of a contour one. A
    // plain Laplacian responds to that weak contrast weakly regardless of
    // whether the frame is actually in focus, so `sharpnessScore` was
    // landing below `kMinSharpnessScore` on sharp-but-washed-out frames
    // just as often as on genuinely blurry ones - which matches "almost
    // always" on light surfaces, and why it went away in a shadow (less
    // washout, more surviving local contrast, nothing to do with the lens
    // actually focusing any differently).
    //
    // CLAHE fixes this the same way it does for contour detection: it
    // rescales *local* contrast rather than applying one global
    // adjustment, so a real edge that was just washed out by exposure
    // regains a strong Laplacian response. A genuinely blurry frame stays
    // low-variance even after CLAHE, since CLAHE can only rescale
    // contrast that's actually present in the frame - it can't recreate
    // high-frequency detail a real blur already destroyed. Same
    // clipLimit/tileGridSize as `DocumentContourDetector._preprocessGray`
    // for consistency; nothing here is CIN-specific enough to warrant a
    // different tuning.
    final clahe = cv.createCLAHE(clipLimit: 2.5, tileGridSize: (8, 8));
    final equalized = clahe.apply(gray);

    final laplacian = cv.laplacian(equalized, cv.MatType.CV_64F);
    // meanStdDev returns a (Scalar mean, Scalar stddev) record - it does
    // NOT take output-parameter Mats (that was an older API version).
    final (_, stddevScalar) = cv.meanStdDev(laplacian);
    final double sigma = stddevScalar.val1;

    laplacian.dispose();
    equalized.dispose();
    if (!isGray) gray.dispose();

    return sigma * sigma;
  }

  bool isSharpEnough(cv.Mat mat) => sharpnessScore(mat) >= kMinSharpnessScore;
}