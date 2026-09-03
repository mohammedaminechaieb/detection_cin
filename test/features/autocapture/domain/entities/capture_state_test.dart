// Tier A - pure Dart entities, no mocks, no platform. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/autocapture/domain/entities/capture_state.dart';

void main() {
  group('QualityIssues', () {
    test('default constructor has no issues', () {
      const issues = QualityIssues();
      expect(issues.hasAny, isFalse);
    });

    test('hasAny is true if any single flag is set', () {
      expect(const QualityIssues(tooBlurry: true).hasAny, isTrue);
      expect(const QualityIssues(tooDark: true).hasAny, isTrue);
      expect(const QualityIssues(tooBright: true).hasAny, isTrue);
      expect(const QualityIssues(unstable: true).hasAny, isTrue);
      expect(const QualityIssues(contentMismatch: true).hasAny, isTrue);
    });

    test('equality is value-based', () {
      const a = QualityIssues(tooBlurry: true, unstable: true);
      const b = QualityIssues(tooBlurry: true, unstable: true);
      const c = QualityIssues(tooBlurry: true, unstable: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('CaptureState', () {
    test('has exactly the five expected states', () {
      expect(CaptureState.values, [
        CaptureState.searching,
        CaptureState.poorQuality,
        CaptureState.holding,
        CaptureState.triggerCapture,
        CaptureState.captured,
      ]);
    });
  });
}
