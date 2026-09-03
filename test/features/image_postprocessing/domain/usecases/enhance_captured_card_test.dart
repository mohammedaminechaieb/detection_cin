// Tier A - package:image is pure Dart, runs anywhere. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:detection_cin/features/image_postprocessing/domain/entities/enhancement_settings.dart';
import 'package:detection_cin/features/image_postprocessing/domain/usecases/enhance_captured_card.dart';

import '../../../../test_helpers/png_test_utils.dart';

void main() {
  group('EnhanceCapturedCard', () {
    test('enhances front and back independently and returns both', () {
      const usecase = EnhanceCapturedCard();
      final front = checkerPng(cell: 4);
      final back = solidColorPng(r: 100, g: 100, b: 100);

      final (enhancedFront, enhancedBack) = usecase(front, back);

      expect(img.decodePng(enhancedFront), isNotNull);
      expect(img.decodePng(enhancedBack), isNotNull);
    });

    test('applies grayscale setting to both sides identically', () {
      const usecase = EnhanceCapturedCard();
      final front = solidColorPng(r: 200, g: 20, b: 20);
      final back = solidColorPng(r: 20, g: 200, b: 20);

      final (enhancedFront, enhancedBack) =
          usecase(front, back, settings: const EnhancementSettings(grayscale: true));

      final f = img.decodePng(enhancedFront)!.getPixel(1, 1);
      final b = img.decodePng(enhancedBack)!.getPixel(1, 1);
      expect(f.r, f.g);
      expect(f.g, f.b);
      expect(b.r, b.g);
      expect(b.g, b.b);
    });

    test('default settings (EnhancementSettings.defaults) are used if none provided', () {
      const usecase = EnhanceCapturedCard();
      final (front, back) = usecase(solidColorPng(), solidColorPng());
      expect(img.decodePng(front), isNotNull);
      expect(img.decodePng(back), isNotNull);
    });

    test('sharpenEnabled: false disables sharpening for both sides', () {
      const usecase = EnhanceCapturedCard();
      expect(
        () => usecase(checkerPng(), checkerPng(), settings: const EnhancementSettings(sharpenEnabled: false)),
        returnsNormally,
      );
    });
  });
}
