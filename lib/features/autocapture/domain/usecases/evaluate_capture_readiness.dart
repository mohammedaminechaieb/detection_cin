import '../../../image_quality/data/datasources/detectors/blur_detector.dart';
import '../../../image_quality/data/datasources/detectors/brightness_detector.dart';
import '../entities/capture_state.dart';
import '../entities/quality_report.dart';

/// Logique de décision pure : à partir d'un [QualityReport], quel(s)
/// contrôle(s) échouent (s'il y en a). Volontairement sans dépendance
/// OpenCV/caméra pour être testable en isolation - tout le travail
/// spécifique caméra/OpenCV se fait en amont, quand les détecteurs
/// produisent le `QualityReport`.
class EvaluateCaptureReadiness {
  const EvaluateCaptureReadiness({
    this.minSharpness = BlurDetector.kMinSharpnessScore,
  });

  final double minSharpness;

  QualityIssues call(QualityReport report) {
    if (!report.quadFound) {
      return const QualityIssues();
    }
    return QualityIssues(
      tooBlurry: report.sharpnessScore < minSharpness,
      tooDark: report.brightness == BrightnessStatus.tooDark,
      tooBright: report.brightness == BrightnessStatus.tooBright,
      unstable: !report.isStable,
    );
  }
}