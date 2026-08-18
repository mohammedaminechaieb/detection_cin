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

  // Same clipLimit/tileGridSize as `DocumentContourDetector._preprocessGray`
  // and `BlurDetector.sharpnessScore` (see the latter for the fuller
  // explanation) - kept identical across all three so "light surface"
  // fixes behave consistently rather than each detector picking its own
  // tuning for what's the same underlying problem.
  static final _clahe = cv.createCLAHE(clipLimit: 2.5, tileGridSize: (8, 8));

  /// CLAHE'd once, here, not per match - templates are loaded exactly
  /// once at startup (see `DetectionIsolateWorker._workerMain`'s
  /// `_WorkerInit` handling), so there's no per-frame cost to this.
  ///
  /// This used to be the actual bug behind "too strict, any change in
  /// luminosity makes it harder to detect": the ROI was CLAHE'd every
  /// frame but the template never was, so `matchTemplate` was comparing
  /// a locally-contrast-equalized live ROI against a raw, un-equalized
  /// template. `TM_CCOEFF_NORMED`'s own normalization only cancels a
  /// *single global* affine brightness/contrast difference between the
  /// two patches (see the correlation formula) - CLAHE's *local, tile-
  /// by-tile, nonlinear* remapping isn't that, so applying it to only
  /// one side introduced a structural mismatch between template and ROI
  /// that hadn't existed before, and how much it distorted the
  /// correlation itself varied with the scene's lighting (since CLAHE's
  /// remapping curve is itself a function of each tile's local
  /// histogram). That's exactly backwards from the goal - CLAHE was
  /// meant to make matching *more* robust to lighting, and instead made
  /// it *more* sensitive to it, on top of whatever baseline sensitivity
  /// already existed. CLAHE'ing both sides with the same parameters
  /// keeps them in the same local-contrast-normalized representation,
  /// so the comparison is consistent regardless of ambient lighting -
  /// which is what actually fixes the light-surface case without
  /// regressing the normal one.
  cv.Mat _prepareTemplate(cv.Mat rawTemplate) => _clahe.apply(rawTemplate);

  cv.Mat loadTemplateFromBytes(Uint8List bytes) {
    final raw = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
    final prepared = _prepareTemplate(raw);
    raw.dispose();
    return prepared;
  }

  cv.Mat loadTemplateFromFile(String path) {
    final raw = cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
    if (raw.isEmpty) {
      throw Exception('Template introuvable : $path');
    }
    final prepared = _prepareTemplate(raw);
    raw.dispose();
    return prepared;
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

    // CLAHE the ROI too, same as the template (see `_prepareTemplate`) -
    // this is the fix for "templates don't work unless in a shadow
    // place" on a light surface/higher ambient light. `TM_CCOEFF_NORMED`
    // already mean/variance-normalizes each patch against itself, so
    // it's invariant to the ROI being uniformly brighter or lower-
    // contrast overall - that part was never the problem. What it can't
    // correct is *non-uniform* illumination within the ROI: real light
    // on a light card rarely lands perfectly evenly, so one side/corner
    // of the logo/flag ROI is often measurably brighter than the other
    // (off-axis light, slight lamination glare, camera angle) - a single
    // global mean/variance normalization over the whole ROI can't undo
    // that local gradient, but a shadow incidentally can, by flattening
    // the light hitting the card in the first place. CLAHE corrects the
    // same thing directly, tile-by-tile, without needing that incidental
    // shade.
    final equalizedRegion = _clahe.apply(grayRegion);
    grayRegion.dispose();

    final result = cv.matchTemplate(equalizedRegion, template, cv.TM_CCOEFF_NORMED);
    equalizedRegion.dispose();
    final (_, maxVal, _, _) = cv.minMaxLoc(result);
    result.dispose();

    return (maxVal >= threshold, maxVal);
  }
}
