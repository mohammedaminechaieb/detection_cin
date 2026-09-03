// Tier A - package:image is pure Dart (no FFI), runs anywhere.
// See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:detection_cin/features/image_postprocessing/data/datasources/card_image_enhancer.dart';

import '../../../../test_helpers/png_test_utils.dart';

void main() {
  group('CardImageEnhancer', () {
    test('returns valid, decodable PNG bytes for valid input', () {
      const enhancer = CardImageEnhancer();
      final input = checkerPng();
      final output = enhancer.enhance(input);

      final decoded = img.decodePng(output);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 40);
    });

    test('invalid/undecodable input is returned unchanged rather than throwing', () {
      const enhancer = CardImageEnhancer();
      final input = garbageBytes();
      final output = enhancer.enhance(input);
      expect(output, same(input));
    });

    test('grayscale: true produces an image where R == G == B per pixel', () {
      const enhancer = CardImageEnhancer(grayscale: true);
      final output = enhancer.enhance(checkerPng());
      final decoded = img.decodePng(output)!;

      for (var y = 0; y < decoded.height; y += 5) {
        for (var x = 0; x < decoded.width; x += 5) {
          final p = decoded.getPixel(x, y);
          expect(p.r, p.g, reason: 'pixel ($x,$y) not gray');
          expect(p.g, p.b, reason: 'pixel ($x,$y) not gray');
        }
      }
    });

    test('grayscale: false (default) keeps color information', () {
      const enhancer = CardImageEnhancer();
      // A pure-red input should stay distinguishably non-gray after
      // contrast/sharpen when grayscale is off.
      final redPng = solidColorPng(r: 200, g: 20, b: 20);
      final output = enhancer.enhance(redPng);
      final decoded = img.decodePng(output)!;
      final p = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
      expect(p.r, greaterThan(p.g + 30));
    });

    test('sharpenAmount <= 0 disables the sharpen step (no crash, still valid PNG)', () {
      const enhancer = CardImageEnhancer(sharpenAmount: 0);
      final output = enhancer.enhance(checkerPng());
      expect(img.decodePng(output), isNotNull);
    });

    test('higher contrast increases the spread between light and dark checker cells', () {
      const lowContrast = CardImageEnhancer(contrast: 1.0, sharpenAmount: 0);
      const highContrast = CardImageEnhancer(contrast: 1.35, sharpenAmount: 0);
      final input = checkerPng(cell: 16);

      final lowOut = img.decodePng(lowContrast.enhance(input))!;
      final highOut = img.decodePng(highContrast.enhance(input))!;

      // Sample one light cell and one dark cell from each output.
      int lightLow = lowOut.getPixel(2, 2).r.toInt();
      int darkLow = lowOut.getPixel(10, 2).r.toInt();
      int lightHigh = highOut.getPixel(2, 2).r.toInt();
      int darkHigh = highOut.getPixel(10, 2).r.toInt();

      expect((lightHigh - darkHigh).abs(), greaterThanOrEqualTo((lightLow - darkLow).abs()));
    });

    test('enhance() is deterministic for identical input/settings', () {
      const enhancer = CardImageEnhancer();
      final input = checkerPng();
      final out1 = enhancer.enhance(input);
      final out2 = enhancer.enhance(input);
      expect(out1, equals(out2));
    });
  });
}
