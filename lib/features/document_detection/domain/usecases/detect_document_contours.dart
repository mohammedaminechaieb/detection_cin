import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../entities/detected_document.dart';
import '../repositories/detection_repository.dart';

class DetectDocumentContours {
  final DetectionRepository repository;

  DetectDocumentContours(this.repository);

  DetectedDocument call(cv.Mat frame) => repository.detectDocument(frame);
}
