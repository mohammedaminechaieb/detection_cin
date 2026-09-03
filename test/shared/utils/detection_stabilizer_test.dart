// Tier A - pure Dart, no mocks, no platform. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/shared/utils/detection_stabilizer.dart';

void main() {
  group('DetectionStabilizer', () {
    test('a key is unstable before any observation', () {
      final s = DetectionStabilizer();
      expect(s.isStable('border'), isFalse);
    });

    test('becomes stable only after framesToConfirm consecutive hits', () {
      final s = DetectionStabilizer(framesToConfirm: 2, framesToReset: 3);
      s.update('border', true);
      expect(s.isStable('border'), isFalse, reason: 'one hit is not enough');
      s.update('border', true);
      expect(s.isStable('border'), isTrue);
    });

    test('a single miss does not immediately destabilize', () {
      final s = DetectionStabilizer(framesToConfirm: 2, framesToReset: 3);
      s.update('border', true);
      s.update('border', true);
      expect(s.isStable('border'), isTrue);

      s.update('border', false);
      expect(s.isStable('border'), isTrue, reason: 'framesToReset is 3, one miss must not flip it');
    });

    test('destabilizes after framesToReset consecutive misses', () {
      final s = DetectionStabilizer(framesToConfirm: 2, framesToReset: 3);
      s.update('border', true);
      s.update('border', true);
      expect(s.isStable('border'), isTrue);

      s.update('border', false);
      s.update('border', false);
      s.update('border', false);
      expect(s.isStable('border'), isFalse);
    });

    test('a hit in the middle of misses resets the miss streak', () {
      final s = DetectionStabilizer(framesToConfirm: 2, framesToReset: 3);
      s.update('border', true);
      s.update('border', true);
      s.update('border', false);
      s.update('border', false);
      s.update('border', true); // interrupts the miss streak
      s.update('border', false);
      s.update('border', false);
      expect(s.isStable('border'), isTrue, reason: 'miss streak was reset by the intervening hit');
    });

    test('per-call framesToConfirm overrides the instance default', () {
      final s = DetectionStabilizer(framesToConfirm: 5, framesToReset: 3);
      s.update('fast_signal', true, framesToConfirm: 1);
      expect(s.isStable('fast_signal'), isTrue);
    });

    test('different keys are tracked independently', () {
      final s = DetectionStabilizer(framesToConfirm: 1, framesToReset: 1);
      s.update('a', true);
      expect(s.isStable('a'), isTrue);
      expect(s.isStable('b'), isFalse);
    });

    test('resetAll clears every key back to unstable', () {
      final s = DetectionStabilizer(framesToConfirm: 1, framesToReset: 1);
      s.update('a', true);
      s.update('b', true);
      expect(s.isStable('a'), isTrue);
      expect(s.isStable('b'), isTrue);

      s.resetAll();
      expect(s.isStable('a'), isFalse);
      expect(s.isStable('b'), isFalse);
    });

    test('a hit right after reset needs framesToConfirm again from zero', () {
      final s = DetectionStabilizer(framesToConfirm: 2, framesToReset: 1);
      s.update('a', true);
      s.update('a', true);
      expect(s.isStable('a'), isTrue);
      s.resetAll();
      s.update('a', true);
      expect(s.isStable('a'), isFalse);
    });
  });
}
