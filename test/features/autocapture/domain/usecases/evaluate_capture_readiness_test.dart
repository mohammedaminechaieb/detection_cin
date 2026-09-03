// Tier A - pure Dart usecase, no mocks, no platform. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/autocapture/domain/usecases/evaluate_capture_readiness.dart';
import 'package:detection_cin/features/autocapture/domain/entities/quality_report.dart';
import 'package:detection_cin/features/image_quality/data/datasources/detectors/brightness_detector.dart';

QualityReport goodReport({
  bool quadFound = true,
  double sharpnessScore = 500,
  BrightnessStatus brightness = BrightnessStatus.ok,
  bool isStable = true,
  bool contentMatched = true,
}) =>
    QualityReport(
      quadFound: quadFound,
      sharpnessScore: sharpnessScore,
      brightness: brightness,
      isStable: isStable,
      contentMatched: contentMatched,
    );

void main() {
  group('EvaluateCaptureReadiness', () {
    test('no quad found -> no issues reported at all (fields are meaningless)', () {
      const usecase = EvaluateCaptureReadiness();
      final issues = usecase(goodReport(quadFound: false));
      expect(issues.hasAny, isFalse);
    });

    test('a fully good report has no issues', () {
      const usecase = EvaluateCaptureReadiness();
      final issues = usecase(goodReport());
      expect(issues.hasAny, isFalse);
    });

    test('sharpness below minSharpness -> tooBlurry', () {
      const usecase = EvaluateCaptureReadiness(minSharpness: 120);
      final issues = usecase(goodReport(sharpnessScore: 119.99));
      expect(issues.tooBlurry, isTrue);
      expect(issues.tooDark, isFalse);
      expect(issues.tooBright, isFalse);
    });

    test('sharpness exactly at threshold is NOT too blurry (strict <)', () {
      const usecase = EvaluateCaptureReadiness(minSharpness: 120);
      final issues = usecase(goodReport(sharpnessScore: 120));
      expect(issues.tooBlurry, isFalse);
    });

    test('BrightnessStatus.tooDark -> tooDark issue only', () {
      const usecase = EvaluateCaptureReadiness();
      final issues = usecase(goodReport(brightness: BrightnessStatus.tooDark));
      expect(issues.tooDark, isTrue);
      expect(issues.tooBright, isFalse);
    });

    test('BrightnessStatus.tooBright -> tooBright issue only', () {
      const usecase = EvaluateCaptureReadiness();
      final issues = usecase(goodReport(brightness: BrightnessStatus.tooBright));
      expect(issues.tooBright, isTrue);
      expect(issues.tooDark, isFalse);
    });

    test('unstable quad -> unstable issue', () {
      const usecase = EvaluateCaptureReadiness();
      final issues = usecase(goodReport(isStable: false));
      expect(issues.unstable, isTrue);
    });

    test('content not matched -> contentMismatch issue', () {
      const usecase = EvaluateCaptureReadiness();
      final issues = usecase(goodReport(contentMatched: false));
      expect(issues.contentMismatch, isTrue);
    });

    test('multiple simultaneous issues are all reported', () {
      const usecase = EvaluateCaptureReadiness();
      final issues = usecase(goodReport(
        sharpnessScore: 1,
        brightness: BrightnessStatus.tooDark,
        isStable: false,
        contentMatched: false,
      ));
      expect(issues.tooBlurry, isTrue);
      expect(issues.tooDark, isTrue);
      expect(issues.unstable, isTrue);
      expect(issues.contentMismatch, isTrue);
      expect(issues.hasAny, isTrue);
    });

    test('custom minSharpness constructor param is honored', () {
      const usecase = EvaluateCaptureReadiness(minSharpness: 1000);
      final issues = usecase(goodReport(sharpnessScore: 500));
      expect(issues.tooBlurry, isTrue, reason: 'below the custom, higher threshold');
    });

    test('default minSharpness matches BlurDetector.kMinSharpnessScore', () {
      const usecase = EvaluateCaptureReadiness();
      expect(usecase.minSharpness, 120.0);
    });
  });
}
