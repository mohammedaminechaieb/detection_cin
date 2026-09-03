// Tier C - needs opencv_dart's native binary, no device required, uses
// synthetic in-memory Mats. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/image_quality/data/datasources/detectors/brightness_detector.dart';

import '../../../../../test_helpers/mat_test_utils.dart';

void main() {
  const detector = BrightnessDetector();

  group('BrightnessDetector.meanBrightness', () {
    test('a uniform gray Mat reports its own value as the mean', () {
      final mat = flatMat(gray: 128);
      expect(detector.meanBrightness(mat), closeTo(128, 0.5));
      mat.dispose();
    });
  });

  group('BrightnessDetector.classify', () {
    test('a dark image classifies as tooDark', () {
      final mat = darkMat(value: 10);
      expect(detector.classify(mat), BrightnessStatus.tooDark);
      mat.dispose();
    });

    test('a mid-range image classifies as ok', () {
      final mat = flatMat(gray: 140);
      expect(detector.classify(mat), BrightnessStatus.ok);
      mat.dispose();
    });

    test('a uniformly very bright (washed-out) image classifies as tooBright via the mean ceiling', () {
      final mat = brightMat(baseValue: 250, highlightFraction: 0.0);
      expect(detector.classify(mat), BrightnessStatus.tooBright);
      mat.dispose();
    });

    test('a legitimately light/white card (moderately high mean, no real hotspot) is NOT flagged tooBright', () {
      // Between kMinMeanBrightness (60) and kMaxMeanBrightness (225): a
      // light card should read as ok, per the class's own doc about why
      // the ceiling was raised from 205.
      final mat = flatMat(gray: 215);
      expect(detector.classify(mat), BrightnessStatus.ok);
      mat.dispose();
    });

    test('a small saturated glare hotspot triggers tooBright via highlight fraction, even with a moderate overall mean', () {
      // Base value chosen to keep the *mean* well under kMaxMeanBrightness,
      // isolating the highlight-fraction path.
      final mat = brightMat(baseValue: 150, highlightFraction: 0.20, highlightValue: 253);
      expect(detector.classify(mat), BrightnessStatus.tooBright);
      mat.dispose();
    });

    test('a highlight fraction below kMaxHighlightFraction does not trip tooBright on its own', () {
      final mat = brightMat(baseValue: 150, highlightFraction: 0.05, highlightValue: 253);
      expect(detector.classify(mat), BrightnessStatus.ok);
      mat.dispose();
    });
  });
}
