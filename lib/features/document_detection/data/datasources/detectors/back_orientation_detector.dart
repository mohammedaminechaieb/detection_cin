import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../domain/entities/detected_document.dart';
import 'barcode_area_detector.dart';
import 'card_rotator.dart';
import 'fingerprint_presence_detector.dart';
import 'separation_line_detector.dart';

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

  /// Correction applied to the winning candidate angle - see the comment
  /// on [detect] below for why this exists. Kept as its own named
  /// constant (rather than an inline `+ 180` at the call site) so it has
  /// exactly one definition to update, and so the assumption it encodes
  /// can be checked in one place: [_assertCorrectionStillValid].
  static const int _kOrientationCorrectionDegrees = 180;

  BackOrientationResult detect(cv.Mat warpedCard) {
    assert(_assertCorrectionStillValid(), '');

    BackOrientationResult? best;
    var bestScore = -1;

    for (final angle in _candidateRotations) {
      final rotated = _rotator.apply(warpedCard, angle);

      final (barcodeFound, barcodeScore, barcodeInPosition) = _barcodeDetector.detect(rotated);
      final (fingerprintFound, fingerprintScore) = _fingerprintDetector.detect(rotated);
      final (lineFound, lineBox, lineScore) = _separationLineDetector.detect(rotated);

      if (!identical(rotated, warpedCard)) {
        rotated.dispose();
      }

      final score = (barcodeFound && barcodeInPosition ? 2 : 0) +
          (fingerprintFound ? 1 : 0) +
          (lineFound ? 1 : 0);

      if (score > bestScore) {
        bestScore = score;
        best = BackOrientationResult(
          // +180 correction: the search above is internally consistent
          // (barcode/fingerprint/line all agree on which candidate wins),
          // but the "right-side-up" layout they were all built against -
          // barcode top, fingerprint bottom-right - was verified to be
          // backwards from the real card by exactly 180 degrees (reported
          // as "the back came flipped 180" after the position-aware
          // barcode fix above made the search converge reliably and
          // consistently onto the *wrong* member of the 0/180 pair,
          // rather than inconsistently onto either member of the 90/270
          // pair like before). Rather than rewrite three detectors' ROI/
          // search-region assumptions (and risk breaking their mutual
          // consistency with each other), it's simpler and lower-risk to
          // correct the single final answer by the one constant offset
          // that's actually wrong.
          rotationDegrees: (angle + _kOrientationCorrectionDegrees) % 360,
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

  /// Ties [_kOrientationCorrectionDegrees] to the specific ROI convention
  /// it's correcting for, so a future retuning of that convention (e.g.
  /// `BarcodeAreaDetector._expectedTopRegionFraction` growing past 0.5,
  /// which would mean "barcode on top" no longer distinguishes top from
  /// bottom) fails an assertion here in debug builds instead of silently
  /// producing a wrong rotation with no indication of why. This does not
  /// re-derive or validate the *correctness* of the 180° figure itself -
  /// that was established empirically against a physical card (see
  /// [detect]'s doc) - only that the convention it depends on hasn't
  /// silently shifted underneath it.
  bool _assertCorrectionStillValid() {
    const expectedTopRegionFraction = 0.45; // BarcodeAreaDetector._expectedTopRegionFraction
    assert(
      expectedTopRegionFraction < 0.5,
      'BackOrientationDetector._kOrientationCorrectionDegrees assumes '
      '"barcode expected in the top half" (BarcodeAreaDetector.'
      '_expectedTopRegionFraction < 0.5) to distinguish right-side-up '
      'from upside-down. That ROI convention changed - re-verify the '
      '180° correction against a physical card before trusting it.',
    );
    return true;
  }
}