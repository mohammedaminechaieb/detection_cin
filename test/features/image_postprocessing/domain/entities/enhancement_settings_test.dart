// Tier A - pure Dart entity, no mocks, no platform. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/image_postprocessing/domain/entities/enhancement_settings.dart';

void main() {
  group('ContrastLevel', () {
    test('factor values are ordered low < normal < high', () {
      expect(ContrastLevel.low.factor, lessThan(ContrastLevel.normal.factor));
      expect(ContrastLevel.normal.factor, lessThan(ContrastLevel.high.factor));
    });

    test('exact documented factor values', () {
      expect(ContrastLevel.low.factor, 1.0);
      expect(ContrastLevel.normal.factor, 1.15);
      expect(ContrastLevel.high.factor, 1.35);
    });

    test('labels are the expected French strings', () {
      expect(ContrastLevel.low.label, 'Faible');
      expect(ContrastLevel.normal.label, 'Normal');
      expect(ContrastLevel.high.label, 'Élevé');
    });
  });

  group('EnhancementSettings', () {
    test('defaults are normal contrast, sharpen on, grayscale off', () {
      const s = EnhancementSettings.defaults;
      expect(s.contrastLevel, ContrastLevel.normal);
      expect(s.sharpenEnabled, isTrue);
      expect(s.grayscale, isFalse);
    });

    test('copyWith overrides only the given fields', () {
      const s = EnhancementSettings.defaults;
      final updated = s.copyWith(grayscale: true);
      expect(updated.grayscale, isTrue);
      expect(updated.contrastLevel, s.contrastLevel);
      expect(updated.sharpenEnabled, s.sharpenEnabled);
    });

    test('copyWith with no args returns equivalent values', () {
      const s = EnhancementSettings(contrastLevel: ContrastLevel.high, sharpenEnabled: false, grayscale: true);
      final same = s.copyWith();
      expect(same.contrastLevel, ContrastLevel.high);
      expect(same.sharpenEnabled, isFalse);
      expect(same.grayscale, isTrue);
    });
  });
}
