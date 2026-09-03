// Tier A - package:image is pure Dart (no FFI), runs anywhere.
// See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:detection_cin/features/image_postprocessing/data/datasources/print_page_composer.dart';

import '../../../../test_helpers/png_test_utils.dart';

void main() {
  group('PrintPageComposer', () {
    test('composes front+back into a page of the configured pageWidth/pageHeight', () {
      const composer = PrintPageComposer(pageWidth: 400, pageHeight: 600, margin: 20, gap: 10);
      final page = composer.compose(solidColorPng(width: 100, height: 60), solidColorPng(width: 100, height: 60));

      final decoded = img.decodePng(page)!;
      expect(decoded.width, 400);
      expect(decoded.height, 600);
    });

    test('page background is white outside the placed images', () {
      const composer = PrintPageComposer(pageWidth: 400, pageHeight: 600, margin: 50, gap: 20);
      final page = composer.compose(
        solidColorPng(width: 50, height: 30, r: 0, g: 0, b: 0),
        solidColorPng(width: 50, height: 30, r: 0, g: 0, b: 0),
      );
      final decoded = img.decodePng(page)!;

      final corner = decoded.getPixel(2, 2);
      expect(corner.r, 255);
      expect(corner.g, 255);
      expect(corner.b, 255);
    });

    test('front slot is placed above the back slot (front pixel row < back pixel row for the same content)', () {
      const composer = PrintPageComposer(pageWidth: 300, pageHeight: 500, margin: 20, gap: 10);
      // Distinct colors so we can tell which decoded region came from which input.
      final front = solidColorPng(width: 100, height: 60, r: 255, g: 0, b: 0);
      final back = solidColorPng(width: 100, height: 60, r: 0, g: 0, b: 255);
      final decoded = img.decodePng(composer.compose(front, back))!;

      final slotHeight = (500 - 20 * 2 - 10) ~/ 2;
      final frontRegionY = 20 + slotHeight ~/ 2;
      final backRegionY = 20 + slotHeight + 10 + slotHeight ~/ 2;
      final centerX = 300 ~/ 2;

      final frontPixel = decoded.getPixel(centerX, frontRegionY);
      final backPixel = decoded.getPixel(centerX, backRegionY);

      expect(frontPixel.r, greaterThan(frontPixel.b), reason: 'front (red) slot should be on top');
      expect(backPixel.b, greaterThan(backPixel.r), reason: 'back (blue) slot should be below');
    });

    test('a non-square image is scaled to fit its slot without distortion beyond aspect-preserving resize', () {
      const composer = PrintPageComposer(pageWidth: 400, pageHeight: 800, margin: 20, gap: 20);
      // 2:1 aspect ratio input.
      final wide = solidColorPng(width: 200, height: 100);
      final page = composer.compose(wide, wide);
      expect(img.decodePng(page), isNotNull);
    });

    test('throws StateError when either input cannot be decoded as PNG', () {
      const composer = PrintPageComposer();
      expect(
        () => composer.compose(garbageBytes(), solidColorPng()),
        throwsA(isA<StateError>()),
      );
      expect(
        () => composer.compose(solidColorPng(), garbageBytes()),
        throwsA(isA<StateError>()),
      );
    });

    test('default page dimensions match A4 @300dpi portrait', () {
      const composer = PrintPageComposer();
      expect(composer.pageWidth, 2480);
      expect(composer.pageHeight, 3508);
    });
  });
}
