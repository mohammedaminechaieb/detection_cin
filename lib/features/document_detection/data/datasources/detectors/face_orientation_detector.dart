import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../domain/entities/detected_document.dart';
import 'card_rotator.dart';

/// Detects the ID photo on a warped card and determines the card's correct
/// orientation by running face detection at all 4 rotations and picking
/// the one with the most confident match.
///
/// The Tunisian CIN's photo always sits in the top-left quadrant when the
/// card is right-side up, so each rotation is only searched in that
/// region - this keeps the 4x search cheap and avoids false positives
/// elsewhere on the card.
class FaceOrientationDetector {
  /// [eager]: when `true` (the default, used by the detection isolate
  /// worker), the Haar cascade is loaded immediately and a failure to
  /// load throws right away - this is what lets the worker's
  /// startup handshake fail fast on a bad cascade path instead of
  /// reporting itself ready and then silently never detecting a face for
  /// the rest of the session. Pass `eager: false` for a detector instance
  /// that may never actually call [detect] (e.g. the main-isolate
  /// repository used only for the manual recrop flow in
  /// `EditCaptureScreen`, which never touches face detection) so it
  /// doesn't pay the cost of loading a cascade classifier it won't use.
  FaceOrientationDetector(String cascadePath, {CardRotator? rotator, bool eager = true})
      : _cascadePath = cascadePath,
        _rotator = rotator ?? const CardRotator() {
    if (eager) _ensureLoaded();
  }

  final String _cascadePath;
  bool _loadAttempted = false;
  cv.CascadeClassifier? _faceCascade;
  final CardRotator _rotator;

  /// Loads the cascade classifier on first use if it wasn't already
  /// loaded eagerly at construction. `CascadeClassifier.load` returns a
  /// `bool` rather than throwing on failure (bad path, corrupt/missing
  /// file), so the return value must be checked explicitly - previously
  /// it was discarded, which meant a bad cascade path could leave
  /// `_faceCascade` set to an empty, non-functional classifier with no
  /// error raised anywhere, silently reading to the user as "front-side
  /// capture never works."
  void _ensureLoaded() {
    if (_loadAttempted) return;
    _loadAttempted = true;
    final cascade = cv.CascadeClassifier.empty();
    if (!cascade.load(_cascadePath)) {
      cascade.dispose();
      throw StateError(
        'FaceOrientationDetector: échec du chargement du classifieur de '
        'visage depuis "$_cascadePath" (chemin incorrect, ou fichier de '
        'cascade absent/corrompu).',
      );
    }
    _faceCascade = cascade;
  }

  static const double _searchRoiWidthFraction = 0.35;
  static const double _searchRoiTopMarginFraction = 0.15;
  static const double _minFaceSizeFraction = 0.10;
  static const double _faceScaleFactor = 1.05;
  static const int _faceMinNeighbors = 8;

  (PhotoDetectionResult, CardRect?) detect(cv.Mat warpedCard) {
    _ensureLoaded();
    if (_faceCascade == null) return (PhotoDetectionResult.none(), null);

    final candidateRotations = [0, 90, 180, 270];

    var bestFound = false;
    var bestAngle = 0;
    var bestConfidence = 0.0;
    CardRect? bestBox;

    for (final angle in candidateRotations) {
      final rotated = _rotator.apply(warpedCard, angle);

      final w = rotated.cols;
      final h = rotated.rows;
      final roiX2 = (w * _searchRoiWidthFraction).toInt();
      final roiY1 = (h * _searchRoiTopMarginFraction).toInt();
      final roi = rotated.region(cv.Rect(0, roiY1, roiX2, h - roiY1));
      final gray = cv.cvtColor(roi, cv.COLOR_BGR2GRAY);
      final minSize = (w * _minFaceSizeFraction).toInt();

      final faces = _faceCascade!.detectMultiScale(
        gray,
        scaleFactor: _faceScaleFactor,
        minNeighbors: _faceMinNeighbors,
        minSize: (minSize, minSize),
      );

      if (faces.isNotEmpty && faces.length.toDouble() > bestConfidence) {
        bestFound = true;
        bestAngle = angle;
        bestConfidence = faces.length.toDouble();

        final f = faces.first;
        bestBox = CardRect(
          f.x.toDouble(),
          (f.y + roiY1).toDouble(),
          f.width.toDouble(),
          f.height.toDouble(),
        );
      }

      gray.dispose();
      roi.dispose();
      // `_rotator.apply` returns the same instance as `warpedCard` (which
      // the caller owns) when angle == 0, so only dispose the Mats we
      // actually allocated here.
      if (!identical(rotated, warpedCard)) {
        rotated.dispose();
      }
    }

    return (
      PhotoDetectionResult(found: bestFound, rotationDegrees: bestAngle, confidence: bestConfidence),
      bestBox,
    );
  }

  /// Releases the native Haar cascade classifier. Previously there was no
  /// way to do this at all - the isolate worker just called `Isolate.
  /// exit()` on shutdown, leaking the cascade's native memory every time
  /// the camera screen (and therefore the worker) was re-entered. Safe to
  /// call more than once.
  void dispose() {
    _faceCascade?.dispose();
    _faceCascade = null;
  }
}
