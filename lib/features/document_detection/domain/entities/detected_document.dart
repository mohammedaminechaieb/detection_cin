import 'dart:ui';

class CardPoint {
  final double x;
  final double y;
  const CardPoint(this.x, this.y);
}

class CardQuad {
  final CardPoint topLeft;
  final CardPoint topRight;
  final CardPoint bottomRight;
  final CardPoint bottomLeft;

  const CardQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  List<Offset> toOffsets() => [
        Offset(topLeft.x, topLeft.y),
        Offset(topRight.x, topRight.y),
        Offset(bottomRight.x, bottomRight.y),
        Offset(bottomLeft.x, bottomLeft.y),
      ];
}

class DetectedDocument {
  final bool isDetected;
  final CardQuad? quad;
  final double score;

  // Which candidate-generation pass produced this quad: 'canny', 'canny_fin',
  // 'adaptive', or 'couleur'. See DocumentDetectionDataSource._findCandidates.
  final String source;

  const DetectedDocument({
    required this.isDetected,
    required this.quad,
    required this.score,
    required this.source,
  });

  factory DetectedDocument.none() =>
      const DetectedDocument(isDetected: false, quad: null, score: 0, source: '');
}

class PhotoDetectionResult {
  final bool found;
  final int rotationDegrees;
  final double confidence;

  const PhotoDetectionResult({
    required this.found,
    required this.rotationDegrees,
    required this.confidence,
  });

  factory PhotoDetectionResult.none() =>
      const PhotoDetectionResult(found: false, rotationDegrees: 0, confidence: 0);
}

class CardRect {
  final double x, y, width, height;
  const CardRect(this.x, this.y, this.width, this.height);
}

/// Result of [BackOrientationDetector]'s search - the back-side
/// equivalent of [PhotoDetectionResult], carrying the winning rotation
/// plus the barcode/fingerprint/separation-line results already computed
/// at that rotation, so callers don't need to re-run those checks a
/// second time at the chosen angle.
class BackOrientationResult {
  final int rotationDegrees;
  final bool barcodeFound;
  final double barcodeScore;
  final bool fingerprintFound;
  final double fingerprintScore;
  final bool separationLineFound;
  final (int, int, int, int)? separationLineBox;
  final double separationLineScore;

  const BackOrientationResult({
    required this.rotationDegrees,
    required this.barcodeFound,
    required this.barcodeScore,
    required this.fingerprintFound,
    required this.fingerprintScore,
    required this.separationLineFound,
    required this.separationLineBox,
    required this.separationLineScore,
  });

  factory BackOrientationResult.none() => const BackOrientationResult(
        rotationDegrees: 0,
        barcodeFound: false,
        barcodeScore: 0,
        fingerprintFound: false,
        fingerprintScore: 0,
        separationLineFound: false,
        separationLineBox: null,
        separationLineScore: 0,
      );
}

class CardAnalysisResult {
  final DetectedDocument document;
  final PhotoDetectionResult photo;
  final CardRect? faceBox;
  final bool logoFound;
  final double logoScore;
  final bool flagFound;
  final double flagScore;

  const CardAnalysisResult({
    required this.document,
    required this.photo,
    required this.faceBox,
    required this.logoFound,
    required this.logoScore,
    required this.flagFound,
    required this.flagScore,
  });

  factory CardAnalysisResult.none() => CardAnalysisResult(
        document: DetectedDocument.none(),
        photo: PhotoDetectionResult.none(),
        faceBox: null,
        logoFound: false,
        logoScore: 0,
        flagFound: false,
        flagScore: 0,
      );
}

class BackAnalysisResult {
  final DetectedDocument document;

  /// The rotation (0/90/180/270) [BackOrientationDetector] picked for
  /// this frame - the back-side counterpart of `CardAnalysisResult.photo.
  /// rotationDegrees`. There's no face to anchor on for the back, so this
  /// is derived from the barcode/fingerprint/separation-line checks
  /// themselves (see `BackOrientationDetector`) rather than computed
  /// separately; it's carried here so a capture request for the back can
  /// reuse the value already found during live analysis instead of
  /// re-running that search once more at capture time.
  final int rotationDegrees;
  final bool barcodeFound;
  final double barcodeScore;
  final bool fingerprintFound;
  final double fingerprintScore;
  final bool separationLineFound;
  final double separationLineScore;

  const BackAnalysisResult({
    required this.document,
    required this.rotationDegrees,
    required this.barcodeFound,
    required this.barcodeScore,
    required this.fingerprintFound,
    required this.fingerprintScore,
    required this.separationLineFound,
    required this.separationLineScore,
  });

  factory BackAnalysisResult.none() => BackAnalysisResult(
        document: DetectedDocument.none(),
        rotationDegrees: 0,
        barcodeFound: false,
        barcodeScore: 0,
        fingerprintFound: false,
        fingerprintScore: 0,
        separationLineFound: false,
        separationLineScore: 0,
      );
}

enum CardSide { front, back }
