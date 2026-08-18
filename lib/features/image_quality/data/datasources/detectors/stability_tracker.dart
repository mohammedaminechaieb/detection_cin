import 'dart:ui';

/// Mesure la stabilité de la position du quad détecté d'une frame à
/// l'autre, pour distinguer "la main tremble encore" de "la carte est
/// posée/tenue immobile" - indépendamment du fait que le contour soit
/// détecté ou non frame par frame. Pure Dart, sans dépendance OpenCV
/// ni caméra, donc testable en isolation.
class StabilityTracker {
  StabilityTracker({
    this.maxCornerDriftRatio = 0.025,
    this.requiredStableFrames = 3,
    this.framesToReset = 2,
  });

  /// Dérive moyenne max tolérée entre deux frames consécutives, comme
  /// fraction de la diagonale du quad lui-même - PAS un nombre de pixels
  /// fixe (voir l'ancien `maxCornerDrift = 8.0`, en pixels bruts dans le
  /// repère de la frame caméra pleine résolution). Un seuil en pixels
  /// absolus ne veut rien dire sans savoir à quelle résolution la caméra
  /// tourne réellement : 8px est large sur un flux 480p mais ridiculement
  /// strict sur un flux 1080p/4K - largement en dessous du tremblement de
  /// main normal en tenant le téléphone, ce qui donnait "n'importe quel
  /// petit mouvement" en rouge en permanence. Une fraction de la propre
  /// diagonale du quad s'adapte automatiquement à la résolution de la
  /// caméra ET à la distance carte-téléphone (un quad plus petit à
  /// l'écran tolère moins de pixels de dérive en absolu, mais la même
  /// fraction relative), donc un seul réglage a un sens indépendamment du
  /// device/preset caméra utilisé.
  final double maxCornerDriftRatio;

  /// Nombre de frames consécutives stables requises avant que
  /// [isStable] devienne vrai.
  final int requiredStableFrames;

  /// Nombre de frames consécutives *au-dessus* du seuil de dérive avant
  /// de considérer que la stabilité est vraiment perdue. Avant, une
  /// seule frame de dérive suffisait à remettre `_stableStreak` à 1 -
  /// donc même déjà stable (`_stableStreak >= requiredStableFrames`),
  /// une seule frame de bruit repartait à 1, faisant retomber [isStable]
  /// à faux immédiatement, et il fallait alors `requiredStableFrames`
  /// frames de plus pour redevenir stable. C'est le "redevient rouge même
  /// après être devenu vert sur un tout petit mouvement" - un `framesTo
  /// Reset` de 2 (au lieu d'un reset sur 1 frame) absorbe le bruit d'une
  /// frame isolée sans jeter tout l'historique de stabilité déjà acquis,
  /// tout en réagissant toujours à un vrai mouvement soutenu.
  final int framesToReset;

  List<Offset>? _lastQuad;
  int _stableStreak = 0;
  int _driftStreak = 0;

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
      _driftStreak = 0;
      return;
    }

    var totalDrift = 0.0;
    for (var i = 0; i < 4; i++) {
      totalDrift += (quad[i] - _lastQuad![i]).distance;
    }
    final avgDrift = totalDrift / 4;

    final diagonal1 = (quad[2] - quad[0]).distance;
    final diagonal2 = (quad[3] - quad[1]).distance;
    final scale = (diagonal1 + diagonal2) / 2;
    final driftRatio = scale > 0 ? avgDrift / scale : 1.0;

    if (driftRatio <= maxCornerDriftRatio) {
      _stableStreak++;
      _driftStreak = 0;
    } else {
      _driftStreak++;
      // Only a real, sustained reset - see [framesToReset]'s doc for why
      // a single stray frame no longer throws the streak away.
      if (_driftStreak >= framesToReset) {
        _stableStreak = 0;
      }
    }
    _lastQuad = quad;
  }

  void reset() {
    _lastQuad = null;
    _stableStreak = 0;
    _driftStreak = 0;
  }

  bool get isStable => _stableStreak >= requiredStableFrames;

  /// 0.0 (vient de démarrer) à 1.0 (stable) - pratique pour un anneau
  /// de progression dans l'UI pendant que l'utilisateur tient la
  /// carte immobile.
  double get progress => (_stableStreak / requiredStableFrames).clamp(0.0, 1.0);
}