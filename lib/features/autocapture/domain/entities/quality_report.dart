import '../../../image_quality/data/datasources/detectors/brightness_detector.dart';

/// Instantané de tous les signaux "cette frame est-elle assez bonne
/// pour capturer" pour une frame analysée. Construit par
/// `DetectionViewModel` (ou l'équivalent qui orchestre les
/// détecteurs) à chaque cycle, et consommé par
/// `EvaluateCaptureReadiness` / `AutocaptureViewModel`.
class QualityReport {
  const QualityReport({
    required this.quadFound,
    required this.sharpnessScore,
    required this.brightness,
    required this.isStable,
    required this.contentMatched,
  });

  /// Un quad a-t-il été trouvé du tout cette frame. Si faux, les
  /// autres champs n'ont pas de sens et doivent être ignorés.
  final bool quadFound;

  final double sharpnessScore;
  final BrightnessStatus brightness;

  /// Résultat de `StabilityTracker.isStable` sur cette frame.
  final bool isStable;

  /// Les contrôles de contenu propres au côté actuel ont-ils tous
  /// réussi (logo + drapeau pour le recto, code-barres + empreinte +
  /// ligne de séparation pour le verso). Calculé par
  /// `DetectionViewModel` à partir de `CardAnalysisResult` /
  /// `BackAnalysisResult` - ce report ne connaît pas le détail des
  /// détecteurs de contenu, juste le résultat agrégé.
  final bool contentMatched;
}