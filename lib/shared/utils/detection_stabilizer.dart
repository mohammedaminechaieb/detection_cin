/// Smooths a noisy per-frame boolean signal so the UI doesn't flicker on
/// isolated bad frames: a signal only becomes "stable" after
/// [framesToConfirm] consecutive hits, and only drops back to unstable
/// after [framesToReset] consecutive misses.
///
/// Each independent signal is tracked under its own [key] (e.g. 'border',
/// 'face', 'logo'), so a single instance can smooth several signals at once.
class DetectionStabilizer {
  DetectionStabilizer({
    this.framesToConfirm = 3,
    this.framesToReset = 2,
  });

  final int framesToConfirm;
  final int framesToReset;

  final Map<String, int> _hitStreaks = {};
  final Map<String, int> _missStreaks = {};
  final Map<String, bool> _stableStates = {};

  bool isStable(String key) => _stableStates[key] ?? false;

  /// Feeds one raw observation for [key]. [framesToConfirm] can be
  /// overridden per call for signals that should confirm faster/slower
  /// than the instance default.
  void update(String key, bool raw, {int? framesToConfirm}) {
    final confirmThreshold = framesToConfirm ?? this.framesToConfirm;
    final hit = _hitStreaks[key] ?? 0;
    final miss = _missStreaks[key] ?? 0;

    if (raw) {
      _hitStreaks[key] = hit + 1;
      _missStreaks[key] = 0;
      if (_hitStreaks[key]! >= confirmThreshold) _stableStates[key] = true;
    } else {
      _missStreaks[key] = miss + 1;
      _hitStreaks[key] = 0;
      if (_missStreaks[key]! >= framesToReset) _stableStates[key] = false;
    }
  }

  void resetAll() {
    _hitStreaks.clear();
    _missStreaks.clear();
    _stableStates.clear();
  }
}
