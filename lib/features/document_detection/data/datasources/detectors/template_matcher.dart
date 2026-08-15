import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Matches known logo/flag templates against fixed regions of an
/// orientation-corrected card image.
class TemplateMatcher {
  const TemplateMatcher();

  static const double _defaultMatchThreshold = 0.6;

  // Region of interest for each template, as fractions of the card's
  // width/height, based on where these elements sit on a right-side-up CIN.
  static const double _logoRoiX1Fraction = 0.55;
  static const double _logoRoiWidthFraction = 0.45;
  static const double _logoRoiHeightFraction = 0.45;

  static const double _flagRoiWidthFraction = 0.30;
  static const double _flagRoiHeightFraction = 0.40;

  cv.Mat loadTemplateFromBytes(Uint8List bytes) => cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);

  cv.Mat loadTemplateFromFile(String path) {
    final template = cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
    if (template.isEmpty) {
      throw Exception('Template introuvable : $path');
    }
    return template;
  }

  (bool, double) detectLogo(cv.Mat orientedCard, cv.Mat templateLogo) {
    final w = orientedCard.cols;
    final h = orientedCard.rows;
    final roi = cv.Rect(
      (w * _logoRoiX1Fraction).toInt(),
      0,
      (w * _logoRoiWidthFraction).toInt(),
      (h * _logoRoiHeightFraction).toInt(),
    );
    return _matchTemplateInRoi(orientedCard, templateLogo, roi);
  }

  (bool, double) detectFlag(cv.Mat orientedCard, cv.Mat templateFlag) {
    final w = orientedCard.cols;
    final h = orientedCard.rows;
    final roi = cv.Rect(0, 0, (w * _flagRoiWidthFraction).toInt(), (h * _flagRoiHeightFraction).toInt());
    return _matchTemplateInRoi(orientedCard, templateFlag, roi);
  }

  // Same clipLimit/tileGridSize as `DocumentContourDetector._preprocessGray`
  // and `BlurDetector.sharpnessScore` (see the latter for the fuller
  // explanation) - kept identical across all three so "light surface"
  // fixes behave consistently rather than each detector picking its own
  // tuning for what's the same underlying problem.
  static final _clahe = cv.createCLAHE(clipLimit: 2.5, tileGridSize: (8, 8));

  (bool, double) _matchTemplateInRoi(
    cv.Mat orientedCard,
    cv.Mat template,
    cv.Rect roi, {
    double threshold = _defaultMatchThreshold,
  }) {
    final region = orientedCard.region(roi);
    final grayRegion = cv.cvtColor(region, cv.COLOR_BGR2GRAY);
    region.dispose();

    if (template.rows > grayRegion.rows || template.cols > grayRegion.cols) {
      grayRegion.dispose();
      return (false, 0.0);
    }

    // CLAHE the ROI before matching - this is the fix for "templates
    // don't work unless in a shadow place" on a light surface/higher
    // ambient light. `TM_CCOEFF_NORMED` already mean/variance-normalizes
    // each patch against itself (both template and ROI are compared as
    // their own mean-subtracted, norm-divided versions), so it's already
    // invariant to the ROI being uniformly brighter or lower-
    // contrast overall - that part was never the problem. What it can't
    // correct is *non-uniform* illumination within the ROI: real light on
    // a light card rarely lands perfectly evenly, so one side/corner of
    // the logo/flag ROI is often measurably brighter than the other
    // (off-axis light, slight lamination glare, camera angle) - a single
    // global mean/variance normalization over the whole ROI can't undo
    // that local gradient, but a shadow incidentally can, by flattening
    // the light hitting the card in the first place. CLAHE corrects the
    // same thing directly, tile-by-tile, without needing that incidental
    // shade - same technique (and same clipLimit/tileGridSize, for
    // consistency) already applied to contour detection
    // (`DocumentContourDetector`) and blur scoring (`BlurDetector`) for
    // spatially-uneven light. The template itself is a clean scanned
    // reference asset with no lighting unevenness to correct, so only the
    // live ROI needs this - `matchTemplate` still compares it against the
    // template's own gray levels as-is.
    final equalizedRegion = _clahe.apply(grayRegion);
    grayRegion.dispose();

    final result = cv.matchTemplate(equalizedRegion, template, cv.TM_CCOEFF_NORMED);
    equalizedRegion.dispose();
    final (_, maxVal, _, _) = cv.minMaxLoc(result);
    result.dispose();

    return (maxVal >= threshold, maxVal);
  }
}
