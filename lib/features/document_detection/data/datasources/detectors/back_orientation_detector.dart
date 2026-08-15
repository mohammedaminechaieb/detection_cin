import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../domain/entities/detected_document.dart';
import 'barcode_area_detector.dart';
import 'card_rotator.dart';
import 'fingerprint_presence_detector.dart';
import 'separation_line_detector.dart';

/// Determines a back-side CIN's correct orientation, the back-side
/// counterpart of [FaceOrientationDetector]'s front-side search: tries
/// all 4 rotations and keeps whichever one the evidence best supports.
///
/// There's no face on the back to search for, so "best supported" is
/// scored on the same three checks the rest of the back-side pipeline
/// already runs per frame - barcode presence, fingerprint texture, and
/// the separation line - rather than a face count. All three assume a
/// right-side-up card (fixed ROIs for the barcode/fingerprint area, a
/// near-horizontal-only search for the line - see
/// [SeparationLineDetector]'s class doc), so running them against
/// whatever rotation the card happens to be sitting at in the frame was
/// the actual cause of "the separation line is searched on the side" -
/// on a card that's physically rotated 90 degrees in frame, the real
/// line is close to *vertical*, which
/// [SeparationLineDetector._maxAngleFromHorizontalDegrees] rejects by
/// design, and the fixed fingerprint/barcode ROIs land on the wrong
/// quadrant entirely. This was never actually wired up to run - see the
/// call site in `DetectionIsolateWorker._analyzeBack`, which used to call
/// these three checks directly on the un-rotated warped card.
///
/// This reuses the same [BarcodeAreaDetector]/[FingerprintPresenceDetector]/
/// [SeparationLineDetector] instances the rest of the back-side pipeline
/// already owns (see `DocumentDetectionDataSource`), so it doesn't load or
/// own any extra state of its own - just runs the existing three checks
/// once per candidate rotation, the same total cost as before per check,
/// just x4. The winning angle's already-computed results are returned
/// directly in [BackOrientationResult] so callers don't need to re-run
/// the checks a second time at the chosen rotation.
class BackOrientationDetector {
  const BackOrientationDetector(
    this._barcodeDetector,
    this._fingerprintDetector,
    this._separationLineDetector, {
    CardRotator rotator = const CardRotator(),
  }) : _rotator = rotator;

  final BarcodeAreaDetector _barcodeDetector;
  final FingerprintPresenceDetector _fingerprintDetector;
  final SeparationLineDetector _separationLineDetector;
  final CardRotator _rotator;

  static const List<int> _candidateRotations = [0, 90, 180, 270];

  BackOrientationResult detect(cv.Mat warpedCard) {
    BackOrientationResult? best;
    var bestScore = -1;

    for (final angle in _candidateRotations) {
      final rotated = _rotator.apply(warpedCard, angle);

      final (barcodeFound, barcodeScore) = _barcodeDetector.detect(rotated);
      final (fingerprintFound, fingerprintScore) = _fingerprintDetector.detect(rotated);
      final (lineFound, lineBox, lineScore) = _separationLineDetector.detect(rotated);

      if (!identical(rotated, warpedCard)) {
        rotated.dispose();
      }

      // Simple vote count (0-3), not a weighted sum of the individual
      // scores - the three checks are on different scales (a fraction, a
      // pixel-variance value, a length ratio) with no shared unit to
      // combine them by, and a plain "how many of the 3 confirmed" count
      // is exactly the same signal `contentMatched` already uses
      // downstream (see `DetectionIsolateWorker._analyzeFrame`), so this
      // stays consistent with how "is this the right side/orientation" is
      // judged everywhere else in the pipeline.
      final score = (barcodeFound ? 1 : 0) + (fingerprintFound ? 1 : 0) + (lineFound ? 1 : 0);

      if (score > bestScore) {
        bestScore = score;
        best = BackOrientationResult(
          rotationDegrees: angle,
          barcodeFound: barcodeFound,
          barcodeScore: barcodeScore,
          fingerprintFound: fingerprintFound,
          fingerprintScore: fingerprintScore,
          separationLineFound: lineFound,
          separationLineBox: lineBox,
          separationLineScore: lineScore,
        );
      }
    }

    // Only reachable if `_candidateRotations` were ever empty - kept as a
    // safe fallback rather than a `!` so a future edit to that list can't
    // turn this into a crash.
    return best ?? BackOrientationResult.none();
  }
}
