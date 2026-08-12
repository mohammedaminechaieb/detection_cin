import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Converts raw camera frame planes into an OpenCV BGR [cv.Mat].
///
/// Handles the two pixel formats the `camera` plugin can produce:
/// BGRA8888 (iOS) and YUV420 (Android, delivered as three separate Y/U/V
/// planes that are repacked into NV21 before OpenCV's color conversion).
///
/// Takes plain fields rather than a `CameraImage` directly so it can run
/// inside `DetectionIsolateWorker` (a background isolate) as well as on
/// the main isolate - `CameraImage`/`Plane` themselves aren't guaranteed
/// safe to send across an isolate boundary, but the raw bytes and simple
/// metadata pulled out into `IsolateFrameInput` are.
///
/// Callers own the returned [cv.Mat] and are responsible for disposing it.
class CameraImageConverter {
  const CameraImageConverter();

  cv.Mat toBgrMat({
    required int width,
    required int height,
    required bool isBgra,
    required List<Uint8List> planeBytes,
    required List<int> planeBytesPerRow,
    required List<int> planeBytesPerPixel,
  }) {
    if (isBgra) {
      return _fromBgra8888(width, height, planeBytes.first);
    }
    return _fromYuv420(width, height, planeBytes, planeBytesPerRow, planeBytesPerPixel);
  }

  cv.Mat _fromBgra8888(int width, int height, Uint8List bytes) {
    final bgraMat = cv.Mat.fromList(height, width, cv.MatType.CV_8UC4, bytes);
    final bgrMat = cv.cvtColor(bgraMat, cv.COLOR_BGRA2BGR);
    bgraMat.dispose();
    return bgrMat;
  }

  cv.Mat _fromYuv420(
    int width,
    int height,
    List<Uint8List> planeBytes,
    List<int> planeBytesPerRow,
    List<int> planeBytesPerPixel,
  ) {
    final nv21Bytes = _packYuv420AsNv21(width, height, planeBytes, planeBytesPerRow, planeBytesPerPixel);
    final yuvMat = cv.Mat.fromList(
      (height * 1.5).toInt(),
      width,
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
  ///
  /// NOTE ON PERFORMANCE (flagged, not changed here - see conversation):
  /// the chroma loop below is a per-pixel Dart-level read+write
  /// (`chromaWidth * chromaHeight` iterations every frame). On Android,
  /// when `uvPixelStride == 2`, U and V are usually two views over the
  /// *same* underlying semi-planar buffer (V's plane starting 1 byte
  /// before U's), which would let a whole output row be copied in one
  /// `setRange` straight from the V plane's bytes instead of pixel by
  /// pixel. I did NOT make that change: whether the V plane's bytes on
  /// this specific `camera` plugin version are a *view* over that shared
  /// buffer (safe to bulk-copy) or an independently-copied `Uint8List`
  /// (bulk-copy would silently produce wrong/scrambled color) isn't
  /// something I can verify without the actual plugin source or a device
  /// to test on - and getting it wrong here corrupts color on every
  /// single frame, silently. If you want to try the fast path: copy
  /// `chromaWidth * 2` bytes from the V plane's bytes starting at
  /// `row * uvRowStride` into the output per row, and check the actual
  /// preview colors immediately (a green/purple tint or scrambled image
  /// means the assumption was wrong for your `camera` version/device).
  Uint8List _packYuv420AsNv21(
    int width,
    int height,
    List<Uint8List> planeBytes,
    List<int> planeBytesPerRow,
    List<int> planeBytesPerPixel,
  ) {
    final yBytes = planeBytes[0];
    final uBytes = planeBytes[1];
    final vBytes = planeBytes[2];

    final nv21 = Uint8List(width * height + 2 * (width ~/ 2) * (height ~/ 2));

    var offset = 0;
    final yRowStride = planeBytesPerRow[0];
    for (var row = 0; row < height; row++) {
      final rowStart = row * yRowStride;
      nv21.setRange(offset, offset + width, yBytes, rowStart);
      offset += width;
    }

    final uvRowStride = planeBytesPerRow[1];
    final uvPixelStride = planeBytesPerPixel[1];
    final chromaHeight = height ~/ 2;
    final chromaWidth = width ~/ 2;

    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final uIndex = row * uvRowStride + col * uvPixelStride;
        final vIndex = row * uvRowStride + col * uvPixelStride;

        nv21[offset++] = vBytes[vIndex];
        nv21[offset++] = uBytes[uIndex];
      }
    }

    return nv21;
  }
}