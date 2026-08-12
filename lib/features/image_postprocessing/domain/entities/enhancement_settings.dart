/// User-chosen enhancement options, picked in `ResultPreviewScreen` and
/// threaded through `PostprocessingViewModel` -> `ProcessCapturedCard` ->
/// `CardImageEnhancer`. Plain Dart (no Flutter/OpenCV/image-package
/// dependency) so it can cross the `compute()` isolate boundary as part
/// of the process input, same as the PNG bytes it travels alongside.
class EnhancementSettings {
  const EnhancementSettings({
    this.contrastLevel = ContrastLevel.normal,
    this.sharpenEnabled = true,
    this.grayscale = false,
  });

  final ContrastLevel contrastLevel;
  final bool sharpenEnabled;
  final bool grayscale;

  static const EnhancementSettings defaults = EnhancementSettings();

  EnhancementSettings copyWith({
    ContrastLevel? contrastLevel,
    bool? sharpenEnabled,
    bool? grayscale,
  }) {
    return EnhancementSettings(
      contrastLevel: contrastLevel ?? this.contrastLevel,
      sharpenEnabled: sharpenEnabled ?? this.sharpenEnabled,
      grayscale: grayscale ?? this.grayscale,
    );
  }
}

/// Maps to `CardImageEnhancer.contrast` - named steps instead of a raw
/// slider value, since a small range (1.0-1.3ish) is where this stays
/// useful for document legibility before it starts clipping/looking odd.
enum ContrastLevel {
  low,
  normal,
  high;

  double get factor {
    switch (this) {
      case ContrastLevel.low:
        return 1.0;
      case ContrastLevel.normal:
        return 1.15;
      case ContrastLevel.high:
        return 1.35;
    }
  }

  String get label {
    switch (this) {
      case ContrastLevel.low:
        return 'Faible';
      case ContrastLevel.normal:
        return 'Normal';
      case ContrastLevel.high:
        return 'Élevé';
    }
  }
}