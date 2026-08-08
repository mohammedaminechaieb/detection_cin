import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:detection_cin/features/image_quality/data/datasources/detectors/stability_tracker.dart';

void main() {
  const quad = [
    Offset(0, 0),
    Offset(100, 0),
    Offset(100, 100),
    Offset(0, 100),
  ];

  const jumpedQuad = [
    Offset(50, 50),
    Offset(150, 50),
    Offset(150, 150),
    Offset(50, 150),
  ];

  group('StabilityTracker', () {
    test('not stable before requiredStableFrames identical-ish frames', () {
      final tracker = StabilityTracker(maxCornerDrift: 5, requiredStableFrames: 3);

      tracker.update(quad);
      tracker.update(quad);
      expect(tracker.isStable, isFalse);

      tracker.update(quad);
      expect(tracker.isStable, isTrue);
    });

    test('a large jump resets the streak instead of accumulating', () {
      final tracker = StabilityTracker(maxCornerDrift: 5, requiredStableFrames: 3);

      tracker.update(quad);
      tracker.update(quad);
      tracker.update(quad);
      expect(tracker.isStable, isTrue);

      tracker.update(jumpedQuad);
      expect(tracker.isStable, isFalse);
    });

    test('losing the quad resets everything', () {
      final tracker = StabilityTracker(maxCornerDrift: 5, requiredStableFrames: 2);

      tracker.update(quad);
      tracker.update(quad);
      expect(tracker.isStable, isTrue);

      tracker.update(null);
      expect(tracker.isStable, isFalse);
      expect(tracker.progress, 0.0);
    });

    test('progress increases monotonically towards 1.0', () {
      final tracker = StabilityTracker(maxCornerDrift: 5, requiredStableFrames: 4);

      tracker.update(quad);
      expect(tracker.progress, 0.25);
      tracker.update(quad);
      expect(tracker.progress, 0.5);
      tracker.update(quad);
      expect(tracker.progress, 0.75);
      tracker.update(quad);
      expect(tracker.progress, 1.0);
    });
  });
}
