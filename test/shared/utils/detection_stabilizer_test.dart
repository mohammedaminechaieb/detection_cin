import 'package:flutter_test/flutter_test.dart';

import 'package:detection_cin/shared/utils/detection_stabilizer.dart';

void main() {
  group('DetectionStabilizer', () {
    test('a key starts out unstable', () {
      final stabilizer = DetectionStabilizer();
      expect(stabilizer.isStable('border'), isFalse);
    });

    test('becomes stable only after framesToConfirm consecutive hits', () {
      final stabilizer = DetectionStabilizer(framesToConfirm: 3, framesToReset: 2);

      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isFalse, reason: '1 hit is not enough');

      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isFalse, reason: '2 hits is not enough');

      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isTrue, reason: '3rd consecutive hit confirms');
    });

    test('a single miss before confirmation resets the hit streak', () {
      final stabilizer = DetectionStabilizer(framesToConfirm: 3, framesToReset: 2);

      stabilizer.update('border', true);
      stabilizer.update('border', true);
      stabilizer.update('border', false); // streak broken before confirming
      stabilizer.update('border', true);
      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isFalse, reason: 'streak restarted, only at 2 hits');

      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isTrue);
    });

    test('drops back to unstable only after framesToReset consecutive misses', () {
      final stabilizer = DetectionStabilizer(framesToConfirm: 2, framesToReset: 2);

      stabilizer.update('border', true);
      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isTrue);

      stabilizer.update('border', false);
      expect(stabilizer.isStable('border'), isTrue, reason: '1 miss should not drop stability yet');

      stabilizer.update('border', false);
      expect(stabilizer.isStable('border'), isFalse, reason: '2nd consecutive miss drops it');
    });

    test('a single hit while stable resets the miss streak', () {
      final stabilizer = DetectionStabilizer(framesToConfirm: 2, framesToReset: 2);

      stabilizer.update('border', true);
      stabilizer.update('border', true);
      stabilizer.update('border', false);
      stabilizer.update('border', true); // miss streak broken before reset threshold
      stabilizer.update('border', false);
      expect(stabilizer.isStable('border'), isTrue, reason: 'miss streak restarted, only at 1 miss');
    });

    test('different keys are tracked independently', () {
      final stabilizer = DetectionStabilizer(framesToConfirm: 1, framesToReset: 1);

      stabilizer.update('face', true);
      stabilizer.update('logo', false);

      expect(stabilizer.isStable('face'), isTrue);
      expect(stabilizer.isStable('logo'), isFalse);
    });

    test('a per-call framesToConfirm override is honored for that call only', () {
      final stabilizer = DetectionStabilizer(framesToConfirm: 5, framesToReset: 2);

      // separation_line uses framesToConfirm: 1 in DetectionViewModel so it
      // reacts immediately instead of waiting on the instance default of 5.
      stabilizer.update('separation_line', true, framesToConfirm: 1);
      expect(stabilizer.isStable('separation_line'), isTrue);

      // the instance default still applies to keys that don't override it.
      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isFalse);
    });

    test('resetAll clears stability, hit streaks, and miss streaks for every key', () {
      final stabilizer = DetectionStabilizer(framesToConfirm: 2, framesToReset: 2);

      stabilizer.update('border', true);
      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isTrue);

      stabilizer.resetAll();
      expect(stabilizer.isStable('border'), isFalse);

      // confirming again from scratch should take the full framesToConfirm,
      // proving the hit streak itself was cleared, not just the stable flag.
      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isFalse);
      stabilizer.update('border', true);
      expect(stabilizer.isStable('border'), isTrue);
    });
  });
}
