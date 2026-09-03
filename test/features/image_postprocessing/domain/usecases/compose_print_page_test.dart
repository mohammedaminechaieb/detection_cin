// Tier A - package:image is pure Dart, runs anywhere. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:detection_cin/features/image_postprocessing/domain/usecases/compose_print_page.dart';

import '../../../../test_helpers/png_test_utils.dart';

void main() {
  group('ComposePrintPage', () {
    test('delegates to PrintPageComposer and returns valid page PNG bytes', () {
      const usecase = ComposePrintPage();
      final page = usecase(solidColorPng(), solidColorPng());
      final decoded = img.decodePng(page);
      expect(decoded, isNotNull);
      expect(decoded!.width, 2480);
      expect(decoded.height, 3508);
    });

    test('propagates a decode failure as StateError', () {
      const usecase = ComposePrintPage();
      expect(() => usecase(garbageBytes(), solidColorPng()), throwsA(isA<StateError>()));
    });
  });
}
