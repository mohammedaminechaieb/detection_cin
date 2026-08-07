import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../entities/detected_document.dart';

abstract class DetectionRepository {
  DetectedDocument detectDocument(cv.Mat frame);

  cv.Mat warpDocument(cv.Mat frame, CardQuad quad);

  (PhotoDetectionResult, CardRect?) detectPhoto(cv.Mat warpedCard);
  cv.Mat loadTemplateFromBytes(Uint8List bytes);
  (bool, double) detectLogo(cv.Mat orientedCard, cv.Mat templateLogo);
  (bool, double) detectFlag(cv.Mat orientedCard, cv.Mat templateFlag);
  cv.Mat applyRotation(cv.Mat image, int degrees);
  void resetTracking();

  (bool, double) detectBarcodePresence(cv.Mat orientedCard);
  (bool, double) detectFingerprintPresence(cv.Mat orientedCard);
  (bool, (int, int, int, int)?, double) detectSeparationLine(cv.Mat orientedCard);
}
