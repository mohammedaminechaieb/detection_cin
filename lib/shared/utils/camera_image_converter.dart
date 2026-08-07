import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Converts a raw [CameraImage] frame from the `camera` plugin into an
/// OpenCV BGR [cv.Mat].
///
/// Handles the two pixel formats the plugin can produce: BGRA8888 (iOS)
/// and YUV420 (Android, delivered as three separate Y/U/V planes that are
/// repacked into NV21 before OpenCV's color conversion).
///
/// Callers own the returned [cv.Mat] and are responsible for disposing it.
class CameraImageConverter {
  const CameraImageConverter();

  cv.Mat toBgrMat(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888) {
      return _fromBgra8888(image);
    }
    return _fromYuv420(image);
  }

  cv.Mat _fromBgra8888(CameraImage image) {
    final plane = image.planes.first;
    final bgraMat = cv.Mat.fromList(
      image.height,
      image.width,
      cv.MatType.CV_8UC4,
      plane.bytes,
    );
    final bgrMat = cv.cvtColor(bgraMat, cv.COLOR_BGRA2BGR);
    bgraMat.dispose();
    return bgrMat;
  }

  cv.Mat _fromYuv420(CameraImage image) {
    final nv21Bytes = _packYuv420AsNv21(image);
    final yuvMat = cv.Mat.fromList(
      (image.height * 1.5).toInt(),
      image.width,
      cv.MatType.CV_8UC1,
      nv21Bytes,
    );
    final bgrMat = cv.cvtColor(yuvMat, cv.COLOR_YUV2BGR_NV21);
    yuvMat.dispose();
    return bgrMat;
  }

  /// Repacks the plugin's separate Y, U, and V planes (which may have
  /// row padding / non-1 pixel strides) into a single contiguous NV21
  /// byte buffer that OpenCV's YUV420-to-BGR conversion expects.
  Uint8List _packYuv420AsNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height + 2 * (width ~/ 2) * (height ~/ 2));

    var offset = 0;
    final yRowStride = yPlane.bytesPerRow.toInt();
    for (var row = 0; row < height; row++) {
      final rowStart = row * yRowStride;
      nv21.setRange(offset, offset + width, yPlane.bytes, rowStart);
      offset += width;
    }

    final uvRowStride = uPlane.bytesPerRow.toInt();
    final uvPixelStride = (uPlane.bytesPerPixel ?? 1).toInt();
    final chromaHeight = height ~/ 2;
    final chromaWidth = width ~/ 2;

    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final uIndex = (row * uvRowStride + col * uvPixelStride).toInt();
        final vIndex = (row * uvRowStride + col * uvPixelStride).toInt();

        nv21[offset++] = vPlane.bytes[vIndex];
        nv21[offset++] = uPlane.bytes[uIndex];
      }
    }

    return nv21;
  }
}
