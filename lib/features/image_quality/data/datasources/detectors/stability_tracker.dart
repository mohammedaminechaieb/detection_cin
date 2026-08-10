import 'dart:ui';

/// Mesure la stabilité de la position du quad détecté d'une frame à
/// l'autre, pour distinguer "la main tremble encore" de "la carte est
/// posée/tenue immobile" - indépendamment du fait que le contour soit
/// détecté ou non frame par frame. Pure Dart, sans dépendance OpenCV
/// ni caméra, donc testable en isolation.
class StabilityTracker {
  StabilityTracker({
    this.maxCornerDrift = 8.0,
    this.requiredStableFrames = 4,
  });

  /// Déplacement moyen max (en pixels, dans le même repère que les
  /// points passés à [update]) toléré entre deux frames consécutives
  /// pour rester considéré comme stable.
  final double maxCornerDrift;

  /// Nombre de frames consécutives stables requises avant que
  /// [isStable] devienne vrai.
  final int requiredStableFrames;

  List<Offset>? _lastQuad;
  int _stableStreak = 0;

  /// Alimente le tracker avec le dernier quad détecté (4 coins, ordre
  /// cohérent d'une frame à l'autre, ex. haut-gauche, haut-droit,
  /// bas-droit, bas-gauche). Passe `null` si aucun quad n'a été
  /// détecté cette frame - ça réinitialise le suivi.
  void update(List<Offset>? quad) {
    if (quad == null || quad.length != 4) {
      reset();
      return;
    }
    if (_lastQuad == null) {
      _lastQuad = quad;
      _stableStreak = 1;
      return;
    }

    var totalDrift = 0.0;
    for (var i = 0; i < 4; i++) {
      totalDrift += (quad[i] - _lastQuad![i]).distance;
    }
    final avgDrift = totalDrift / 4;

    // Un dépassement du seuil ne remet pas le compteur à zéro : cette
    // frame devient simplement la nouvelle référence, pour ne pas
    // pénaliser trop fort une seule frame parasite.
    _stableStreak = avgDrift <= maxCornerDrift ? _stableStreak + 1 : 1;
    _lastQuad = quad;
  }

  void reset() {
    _lastQuad = null;
    _stableStreak = 0;
  }

  bool get isStable => _stableStreak >= requiredStableFrames;

  /// 0.0 (vient de démarrer) à 1.0 (stable) - pratique pour un anneau
  /// de progression dans l'UI pendant que l'utilisateur tient la
  /// carte immobile.
  double get progress => (_stableStreak / requiredStableFrames).clamp(0.0, 1.0);
}