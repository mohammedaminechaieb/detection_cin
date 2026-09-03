// Tier A helper (see test/README.md). `package:image` is pure Dart (no
// FFI/native binary), so these run anywhere `flutter test` runs - used by
// the image_postprocessing tests to build tiny real PNGs in-memory
// instead of shipping binary fixture files in the repo.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A small solid-color PNG, [width]x[height], RGB [r],[g],[b].
Uint8List solidColorPng({
  int width = 64,
  int height = 40,
  int r = 200,
  int g = 200,
  int b = 200,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodePng(image));
}

/// A small PNG with a checker pattern - gives contrast/sharpen
/// operations something non-trivial to act on (a flat color image can
/// silently "pass" a broken convolution kernel).
Uint8List checkerPng({int width = 64, int height = 40, int cell = 8}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final isDark = ((x ~/ cell) + (y ~/ cell)).isEven;
      image.setPixelRgb(x, y, isDark ? 30 : 225, isDark ? 30 : 225, isDark ? 30 : 225);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Bytes that are not a valid PNG at all - for decode-failure paths.
Uint8List garbageBytes() => Uint8List.fromList(List.generate(16, (i) => i));
