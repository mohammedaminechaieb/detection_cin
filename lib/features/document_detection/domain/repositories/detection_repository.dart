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

  (bool, double, bool) detectBarcodePresence(cv.Mat orientedCard);
  (bool, double) detectFingerprintPresence(cv.Mat orientedCard);
  (bool, (int, int, int, int)?, double) detectSeparationLine(cv.Mat orientedCard);

  /// Back-side counterpart of [detectPhoto]'s rotation search - see
  /// `BackOrientationDetector`. Takes the raw `warped` card, not an
  /// already-oriented one.
  BackOrientationResult detectBackOrientation(cv.Mat warpedCard);

  /// Encode [image] en PNG pour sauvegarde/affichage (ex. après une
  /// capture validée par l'autocapture). Ne modifie ni ne libère [image].
  Uint8List encodeToPng(cv.Mat image);

  /// Décode des octets PNG (ex. une carte déjà capturée) en [cv.Mat].
  /// L'appelant est responsable de disposer le Mat retourné.
  cv.Mat decodePng(Uint8List pngBytes);
}