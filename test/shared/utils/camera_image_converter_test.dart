// Tier C - needs opencv_dart's native binary, no device/camera required;
// builds synthetic camera-plane byte buffers by hand instead of using a
// real CameraImage (which needs the camera plugin/a device anyway).
// See test/README.md.
//
// ASSOMPTION NON VÉRIFIÉE: cv.mean(mat).val1/val2/val3 return channel
// means in the Mat's own channel order (B, G, R for a 3-channel BGR
// Mat) - same assumption BrightnessDetector already relies on. If
// opencv_dart's Scalar ordering differs, adjust the val1/2/3 mapping
// below rather than the converter itself.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:detection_cin/shared/utils/camera_image_converter.dart';

void main() {
  const converter = CameraImageConverter();

  group('CameraImageConverter.toBgrMat - BGRA8888 path (iOS)', () {
    test('produces a 3-channel Mat of the requested width/height', () {
      const width = 8;
      const height = 6;
      final bytes = Uint8List(width * height * 4);
      // Fill every pixel with B=10, G=20, R=30, A=255.
      for (var i = 0; i < bytes.length; i += 4) {
        bytes[i] = 10;
        bytes[i + 1] = 20;
        bytes[i + 2] = 30;
        bytes[i + 3] = 255;
      }

      final mat = converter.toBgrMat(
        width: width,
        height: height,
        isBgra: true,
        planeBytes: [bytes],
        planeBytesPerRow: [width * 4],
        planeBytesPerPixel: [4],
      );

      expect(mat.channels, 3);
      expect(mat.cols, width);
      expect(mat.rows, height);
      mat.dispose();
    });

    test('preserves color: uniform BGRA input yields matching-mean BGR output', () {
      const width = 4;
      const height = 4;
      final bytes = Uint8List(width * height * 4);
      for (var i = 0; i < bytes.length; i += 4) {
        bytes[i] = 50; // B
        bytes[i + 1] = 100; // G
        bytes[i + 2] = 150; // R
        bytes[i + 3] = 255; // A
      }

      final mat = converter.toBgrMat(
        width: width,
        height: height,
        isBgra: true,
        planeBytes: [bytes],
        planeBytesPerRow: [width * 4],
        planeBytesPerPixel: [4],
      );

      final mean = cv.mean(mat);
      expect(mean.val1, closeTo(50, 1));
      expect(mean.val2, closeTo(100, 1));
      expect(mean.val3, closeTo(150, 1));
      mat.dispose();
    });
  });

  group('CameraImageConverter.toBgrMat - YUV420 path (Android, planar, pixelStride 1)', () {
    test('a flat mid-gray Y plane with neutral (128) chroma converts to a roughly gray BGR image', () {
      const width = 8;
      const height = 8; // must be even for 4:2:0 chroma subsampling
      final chromaW = width ~/ 2;
      final chromaH = height ~/ 2;

      final yPlane = Uint8List(width * height)..fillRange(0, width * height, 128);
      final uPlane = Uint8List(chromaW * chromaH)..fillRange(0, chromaW * chromaH, 128);
      final vPlane = Uint8List(chromaW * chromaH)..fillRange(0, chromaW * chromaH, 128);

      final mat = converter.toBgrMat(
        width: width,
        height: height,
        isBgra: false,
        planeBytes: [yPlane, uPlane, vPlane],
        planeBytesPerRow: [width, chromaW, chromaW],
        planeBytesPerPixel: [1, 1, 1],
      );

      expect(mat.channels, 3);
      expect(mat.cols, width);
      expect(mat.rows, height);

      final mean = cv.mean(mat);
      // Neutral chroma (U=V=128) should decode close to gray on all
      // three channels, allowing generous tolerance for YUV<->RGB
      // rounding.
      expect(mean.val1, closeTo(128, 10));
      expect(mean.val2, closeTo(128, 10));
      expect(mean.val3, closeTo(128, 10));

      mat.dispose();
    });

    test('handles a non-1 uvPixelStride (interleaved chroma, common on Android)', () {
      const width = 8;
      const height = 8;
      final chromaW = width ~/ 2;
      final chromaH = height ~/ 2;

      final yPlane = Uint8List(width * height)..fillRange(0, width * height, 100);
      // Interleaved: stride 2, so plane length must cover every-other-byte access.
      final uPlane = Uint8List(chromaW * chromaH * 2)..fillRange(0, chromaW * chromaH * 2, 128);
      final vPlane = Uint8List(chromaW * chromaH * 2)..fillRange(0, chromaW * chromaH * 2, 128);

      expect(
        () => converter.toBgrMat(
          width: width,
          height: height,
          isBgra: false,
          planeBytes: [yPlane, uPlane, vPlane],
          planeBytesPerRow: [width, chromaW * 2, chromaW * 2],
          planeBytesPerPixel: [1, 2, 2],
        ),
        returnsNormally,
      );
    });
  });
}
