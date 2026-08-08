/// États du flux d'autocapture de l'étape 3. Volontairement agnostique
/// recto/verso pour l'instant - il se contente de répondre "est-ce
/// qu'une carte, correctement cadrée, est assez bonne pour être
/// capturée".
enum CaptureState {
  /// Aucun quad détecté pour l'instant.
  searching,

  /// Un quad est détecté mais au moins un contrôle qualité échoue.
  poorQuality,

  /// Tous les contrôles passent, le compte à rebours avant
  /// déclenchement est en cours.
  holding,

  /// Assez de frames consécutives bonnes ont été vues - à l'appelant
  /// de déclencher la capture réelle maintenant.
  triggerCapture,

  /// La capture a été déclenchée pour ce cycle ; l'état reste ici
  /// jusqu'à un appel explicite à `AutocaptureViewModel.reset()`.
  captured,
}

/// Quel(s) contrôle(s) échoue(nt) actuellement, pour le feedback UI
/// ("Rapprochez-vous", "Trop sombre", "Tenez stable"...). Plusieurs
/// peuvent être vrais en même temps.
class QualityIssues {
  const QualityIssues({
    this.tooBlurry = false,
    this.tooDark = false,
    this.tooBright = false,
    this.unstable = false,
  });

  final bool tooBlurry;
  final bool tooDark;
  final bool tooBright;
  final bool unstable;

  bool get hasAny => tooBlurry || tooDark || tooBright || unstable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QualityIssues &&
          tooBlurry == other.tooBlurry &&
          tooDark == other.tooDark &&
          tooBright == other.tooBright &&
          unstable == other.unstable;

  @override
  int get hashCode => Object.hash(tooBlurry, tooDark, tooBright, unstable);
}