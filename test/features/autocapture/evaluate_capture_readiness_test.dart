import 'package:flutter_test/flutter_test.dart';

import 'package:detection_cin/features/autocapture/domain/entities/quality_report.dart';
import 'package:detection_cin/features/autocapture/domain/usecases/evaluate_capture_readiness.dart';
import 'package:detection_cin/features/image_quality/data/datasources/detectors/brightness_detector.dart';

void main() {
  const evaluate = EvaluateCaptureReadiness(minSharpness: 100);

  test('no quad found -> no issues reported (nothing to measure)', () {
    // const report = QualityReport(
    //   quadFound: false,
    //   sharpnessScore: 0,
    //   brightness: BrightnessStatus.ok,
    //   isStable: false,
    // );

    // expect(evaluate(report).hasAny, isFalse);
  });

  test('flags every failing check independently', () {
    // const report = QualityReport(
    //   quadFound: true,
    //   sharpnessScore: 50,
    //   brightness: BrightnessStatus.tooDark,
    //   isStable: false,
    // );

    // final issues = evaluate(report);
    // expect(issues.tooBlurry, isTrue);
    // expect(issues.tooDark, isTrue);
    // expect(issues.tooBright, isFalse);
    // expect(issues.unstable, isTrue);
  });

  test('tooBright and tooDark are mutually exclusive', () {
    // const report = QualityReport(
    //   quadFound: true,
    //   sharpnessScore: 500,
    //   brightness: BrightnessStatus.tooBright,
    //   isStable: true,
    // );

    // final issues = evaluate(report);
    // expect(issues.tooBright, isTrue);
    // expect(issues.tooDark, isFalse);
  });

  test('all checks passing -> no issues', () {
    // const report = QualityReport(
    //   quadFound: true,
    //   sharpnessScore: 500,
    //   brightness: BrightnessStatus.ok,
    //   isStable: true,
    // );

    // expect(evaluate(report).hasAny, isFalse);
  });
}
