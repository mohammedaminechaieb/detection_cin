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
  });

  /// Un quad a-t-il été trouvé du tout cette frame. Si faux, les
  /// autres champs n'ont pas de sens et doivent être ignorés.
  final bool quadFound;

  final double sharpnessScore;
  final BrightnessStatus brightness;

  /// Résultat de `StabilityTracker.isStable` sur cette frame.
  final bool isStable;
}