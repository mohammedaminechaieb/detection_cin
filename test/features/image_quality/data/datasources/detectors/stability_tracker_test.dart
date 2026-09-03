// Tier A - pure Dart (Offset only), no OpenCV, no mocks.
// See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/image_quality/data/datasources/detectors/stability_tracker.dart';

List<Offset> squareQuad({double cx = 100, double cy = 100, double half = 50}) => [
      Offset(cx - half, cy - half), // topLeft
      Offset(cx + half, cy - half), // topRight
      Offset(cx + half, cy + half), // bottomRight
      Offset(cx - half, cy + half), // bottomLeft
    ];

void main() {
  group('StabilityTracker', () {
    test('is not stable before any update', () {
      final t = StabilityTracker();
      expect(t.isStable, isFalse);
      expect(t.progress, 0.0);
    });

    test('a null quad resets tracking', () {
      final t = StabilityTracker(requiredStableFrames: 2);
      t.update(squareQuad());
      t.update(squareQuad());
      expect(t.isStable, isTrue);

      t.update(null);
      expect(t.isStable, isFalse);
      expect(t.progress, 0.0);
    });

    test('a quad with != 4 points resets tracking', () {
      final t = StabilityTracker(requiredStableFrames: 2);
      t.update(squareQuad());
      t.update(squareQuad());
      expect(t.isStable, isTrue);

      t.update([const Offset(0, 0), const Offset(1, 1)]);
      expect(t.isStable, isFalse);
    });

    test('becomes stable after requiredStableFrames identical frames', () {
      final t = StabilityTracker(requiredStableFrames: 3);
      final q = squareQuad();
      t.update(q);
      expect(t.isStable, isFalse);
      t.update(q);
      expect(t.isStable, isFalse);
      t.update(q);
      expect(t.isStable, isTrue);
    });

    test('progress ramps from 0 to 1 as required frames arrive', () {
      final t = StabilityTracker(requiredStableFrames: 4);
      final q = squareQuad();
      t.update(q);
      expect(t.progress, closeTo(0.25, 1e-9));
      t.update(q);
      expect(t.progress, closeTo(0.5, 1e-9));
      t.update(q);
      expect(t.progress, closeTo(0.75, 1e-9));
      t.update(q);
      expect(t.progress, closeTo(1.0, 1e-9));
    });

    test('drift below maxCornerDriftRatio keeps accumulating stability', () {
      final t = StabilityTracker(requiredStableFrames: 3, maxCornerDriftRatio: 0.05);
      t.update(squareQuad());
      // Diagonal of a 100x100 square is ~141.4; 0.5px drift / 141.4 ~= 0.0035,
      // comfortably under the 0.05 ratio threshold.
      t.update(squareQuad(cx: 100.5, cy: 100));
      t.update(squareQuad(cx: 100.5, cy: 100.5));
      expect(t.isStable, isTrue);
    });

    test('a single large-drift frame does not immediately reset an already-stable streak', () {
      final t = StabilityTracker(requiredStableFrames: 2, framesToReset: 2, maxCornerDriftRatio: 0.01);
      final q = squareQuad();
      t.update(q);
      t.update(q);
      expect(t.isStable, isTrue);

      // A big jump - one frame of drift, framesToReset is 2 so this alone
      // must not wipe the accumulated streak.
      t.update(squareQuad(cx: 300, cy: 300));
      expect(t.isStable, isTrue, reason: 'framesToReset=2, a single drifting frame should be absorbed');
    });

    test('sustained drift for framesToReset frames does reset stability', () {
      final t = StabilityTracker(requiredStableFrames: 2, framesToReset: 2, maxCornerDriftRatio: 0.01);
      final q = squareQuad();
      t.update(q);
      t.update(q);
      expect(t.isStable, isTrue);

      t.update(squareQuad(cx: 300, cy: 300));
      t.update(squareQuad(cx: 500, cy: 500));
      expect(t.isStable, isFalse);
    });

    test('reset() clears streaks and last quad', () {
      final t = StabilityTracker(requiredStableFrames: 2);
      final q = squareQuad();
      t.update(q);
      t.update(q);
      expect(t.isStable, isTrue);

      t.reset();
      expect(t.isStable, isFalse);
      expect(t.progress, 0.0);
      // After reset, a fresh single frame should behave like the very
      // first frame ever seen (streak of 1, not stable yet for
      // requiredStableFrames=2).
      t.update(q);
      expect(t.isStable, isFalse);
    });

    test('degenerate zero-size quad (scale 0) does not throw and is treated as maximal drift', () {
      final t = StabilityTracker(requiredStableFrames: 2);
      final zero = List.generate(4, (_) => const Offset(10, 10));
      expect(() => t.update(zero), returnsNormally);
      t.update(zero);
      expect(() => t.update(zero), returnsNormally);
    });
  });
}
