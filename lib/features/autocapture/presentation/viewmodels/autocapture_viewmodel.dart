import 'package:flutter/foundation.dart';

import '../../domain/entities/capture_state.dart';
import '../../domain/entities/quality_report.dart';
import '../../domain/usecases/evaluate_capture_readiness.dart';

/// Pilote la state machine d'autocapture de l'étape 3. Alimente-le
/// avec un [QualityReport] à chaque frame analysée via [onFrame] ; il
/// expose [state] et [issues] pour l'UI, et appelle [onCaptureReady]
/// une seule fois par cycle quand la capture peut être déclenchée.
class AutocaptureViewModel extends ChangeNotifier {
  AutocaptureViewModel({
    EvaluateCaptureReadiness? evaluateReadiness,
    this.requiredGoodFrames = 5,
    this.onCaptureReady,
  }) : _evaluateReadiness = evaluateReadiness ?? const EvaluateCaptureReadiness();

  final EvaluateCaptureReadiness _evaluateReadiness;

  /// Nombre de frames consécutives devant passer tous les contrôles
  /// avant que la capture se déclenche. Au débit d'analyse throttlé
  /// existant (~10-15 fps côté DetectionViewModel), ça correspond
  /// grosso modo à 0.7-1s de "tout est bon". À ajuster une fois testé
  /// sur device.
  final int requiredGoodFrames;

  /// Appelé exactement une fois par cycle de capture, quand [state]
  /// passe à [CaptureState.triggerCapture].
  final VoidCallback? onCaptureReady;

  CaptureState _state = CaptureState.searching;
  CaptureState get state => _state;

  QualityIssues _issues = const QualityIssues();
  QualityIssues get issues => _issues;

  int _goodStreak = 0;

  /// Progression du "hold" vers la capture, 0.0 à 1.0.
  double get holdProgress => (_goodStreak / requiredGoodFrames).clamp(0.0, 1.0);

  void onFrame(QualityReport report) {
    if (_state == CaptureState.captured) return; // terminal jusqu'à reset()

    if (!report.quadFound) {
      _goodStreak = 0;
      _transition(CaptureState.searching, const QualityIssues());
      return;
    }

    final issues = _evaluateReadiness(report);

    if (issues.hasAny) {
      _goodStreak = 0;
      _transition(CaptureState.poorQuality, issues);
      return;
    }

    _goodStreak++;
    if (_goodStreak >= requiredGoodFrames) {
      _state = CaptureState.captured; // latch avant le callback
      _issues = const QualityIssues();
      notifyListeners();
      onCaptureReady?.call();
      return;
    }

    _transition(CaptureState.holding, const QualityIssues());
  }

  /// À appeler une fois la capture déclenchée traitée par l'appelant
  /// pour démarrer un nouveau cycle (ex. après le recto, pour le verso).
  void reset() {
    _state = CaptureState.searching;
    _issues = const QualityIssues();
    _goodStreak = 0;
    notifyListeners();
  }

  void _transition(CaptureState next, QualityIssues issues) {
    if (_state == next && _issues == issues) return;
    _state = next;
    _issues = issues;
    notifyListeners();
  }
}