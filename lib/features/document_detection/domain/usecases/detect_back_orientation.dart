import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../repositories/detection_repository.dart';

/// Détermine l'orientation correcte du verso en testant les 4 rotations
/// possibles (0/90/180/270) et en choisissant celle qui maximise la
/// présence combinée du code-barres, de l'empreinte et de la ligne de
/// séparation - le verso n'a pas de visage à chercher (contrairement au
/// recto, voir `PhotoDetectionResult.rotationDegrees`), donc ce sont les
/// seuls signaux de contenu disponibles pour détecter l'orientation.
///
/// Ne dépend que de [DetectionRepository] (déjà entièrement vu et
/// utilisé ailleurs dans ce fichier), pas de detecteurs internes non
/// vérifiés.
///
/// COÛT : relance les 3 détecteurs de contenu sur les 4 rotations, donc
/// ~4x le coût d'une frame normale. Volontairement appelé une seule fois,
/// au moment de la capture (voir `DetectionViewModel.onFrame`), jamais à
/// chaque frame - sinon ça ralentirait la détection live du verso.
class DetectBackOrientation {
  const DetectBackOrientation(this.repository);

  final DetectionRepository repository;

  static const _candidateRotations = [0, 90, 180, 270];

  /// Retourne la rotation (en degrés) à appliquer pour remettre [warpedCard]
  /// à l'endroit, avec un score de confiance (plus haut = meilleur ajustement,
  /// pas de borne supérieure fixe - utile seulement pour comparer les 4
  /// candidats entre eux).
  (int rotationDegrees, double confidence) call(cv.Mat warpedCard) {
    var bestAngle = 0;
    var bestScore = double.negativeInfinity;

    for (final angle in _candidateRotations) {
      final rotated = repository.applyRotation(warpedCard, angle);

      final (barcodeFound, barcodeScore) = repository.detectBarcodePresence(rotated);
      final (fingerprintFound, _) = repository.detectFingerprintPresence(rotated);
      final (lineFound, _, lineScore) = repository.detectSeparationLine(rotated);

      // fingerprintScore is deliberately excluded here: it's a raw Laplacian
      // variance (from FingerprintPresenceDetector's blur/texture check),
      // on a completely different scale from barcodeScore/lineScore, and
      // including it distorted rotation selection (a sharp but wrongly
      // rotated candidate could out-score a correctly rotated one just from
      // texture variance). fingerprintFound still contributes via `hits`.
      final hits = (barcodeFound ? 1 : 0) + (fingerprintFound ? 1 : 0) + (lineFound ? 1 : 0);
      final score = hits * 10 + barcodeScore + lineScore;

      if (!identical(rotated, warpedCard)) {
        rotated.dispose();
      }

      if (score > bestScore) {
        bestScore = score;
        bestAngle = angle;
      }
    }

    return (bestAngle, bestScore);
  }
}