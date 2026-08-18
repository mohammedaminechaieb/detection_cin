import 'package:flutter/foundation.dart';

import '../../../../shared/utils/detection_stabilizer.dart';
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
    this.requiredGoodFrames = 2,
    this.onCaptureReady,
  })  : _evaluateReadiness = evaluateReadiness ?? const EvaluateCaptureReadiness(),
        // `framesToConfirm: 1` - going back to "ok" should feel instant,
        // there's no reason to delay the good case. `framesToReset: 2` -
        // this is the actual flicker fix: every individual signal that
        // feeds `QualityReport` (sharpness, brightness, stability,
        // content match) is its own per-frame OpenCV measurement with
        // some frame-to-frame noise of its own - blur score especially,
        // since a borderline (e.g. light-surface) frame sits right at
        // `kMinSharpnessScore` even after the CLAHE fix, and a single
        // frame can dip under it while everything around it is fine.
        // Before this, one such stray frame flipped `state` straight to
        // `poorQuality` (and reset `_goodStreak` to 0), which is exactly
        // the "flickers between ne bougez plus and image floue, takes
        // forever, sometimes drops from all-green back to red" pattern -
        // requiring 2 consecutive bad frames before actually treating it
        // as bad absorbs that single-frame noise the same way
        // `SeparationLineDetector`'s own confirmation already does at
        // the detector level (see `framesToConfirm: 2` in
        // `DetectionIsolateWorker._analyzeBack`) - this is that same
        // idea, one layer up, applied to the aggregate readiness signal.
        _okStabilizer = DetectionStabilizer(framesToConfirm: 1, framesToReset: 2);

  final EvaluateCaptureReadiness _evaluateReadiness;
  final DetectionStabilizer _okStabilizer;

  /// Nombre de frames consécutives devant passer tous les contrôles
  /// avant que la capture se déclenche. Réduit de 8/10 à 3, puis à 2 -
  /// "tout devient vert mais prend du temps à capturer" avec 3 restait
  /// vrai même une fois le flicker corrigé (voir `_okStabilizer`
  /// au-dessus) : 3 *bonnes* frames d'affilée, même sans flicker
  /// visible, correspondait encore à ~1s au débit throttlé existant
  /// (~350ms/frame côté DetectionViewModel). 2 reste suffisant pour
  /// éviter un déclenchement sur une unique frame chanceuse (le vrai
  /// garde-fou contre les faux positifs isolés est de toute façon
  /// `_okStabilizer`, pas ce compteur) tout en coupant le temps de
  /// capture perçu d'un tiers. À ajuster une fois testé sur device.
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
      _okStabilizer.resetAll();
      _transition(CaptureState.searching, const QualityIssues());
      return;
    }

    final issues = _evaluateReadiness(report);
    _okStabilizer.update('ok', !issues.hasAny);

    // Debounced, not the raw `issues.hasAny` - see the stabilizer's
    // construction above for why. A single stray bad frame no longer
    // costs progress OR flips the displayed message; only 2 consecutive
    // bad frames do.
    if (!_okStabilizer.isStable('ok')) {
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
    _okStabilizer.resetAll();
    notifyListeners();
  }

  void _transition(CaptureState next, QualityIssues issues) {
    if (_state == next && _issues == issues) return;
    _state = next;
    _issues = issues;
    notifyListeners();
  }
}