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

    final result = cv.matchTemplate(grayRegion, template, cv.TM_CCOEFF_NORMED);
    grayRegion.dispose();
    final (_, maxVal, _, _) = cv.minMaxLoc(result);
    result.dispose();

    return (maxVal >= threshold, maxVal);
  }
}
