import 'dart:math' as math;
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../domain/entities/detected_document.dart';

const double kCardRatio = 85.6 / 54.0;
const int kOutW = 856;
const int kOutH = 540;
const double kMinScore = 0.35;

class _Candidate {
  final CardQuad quad;
  final double score;
  final String source;
  _Candidate(this.quad, this.score, this.source);
}

class DocumentDetectionDataSource {
  cv.CascadeClassifier? _faceCascade;
  cv.BarcodeDetector? _barcodeDetector;

  static final _kernel5 = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
  static final _kernel9 = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
  static final _kernel15 = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
  static const double _earlyExitScore = 0.75;

  DocumentDetectionDataSource(String cascadePath) {
    _faceCascade = cv.CascadeClassifier.empty();
    _faceCascade!.load(cascadePath);
  }

  CardQuad _orderPoints(List<cv.Point2f> pts) {
    final sums = pts.map((p) => p.x + p.y).toList();
    final diffs = pts.map((p) => p.y - p.x).toList();

    final tl = pts[sums.indexOf(sums.reduce(math.min))];
    final br = pts[sums.indexOf(sums.reduce(math.max))];
    final tr = pts[diffs.indexOf(diffs.reduce(math.min))];
    final bl = pts[diffs.indexOf(diffs.reduce(math.max))];

    return CardQuad(
      topLeft: CardPoint(tl.x, tl.y),
      topRight: CardPoint(tr.x, tr.y),
      bottomRight: CardPoint(br.x, br.y),
      bottomLeft: CardPoint(bl.x, bl.y),
    );
  }

  double _dist(CardPoint a, CardPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  double _quadArea(CardQuad q) {
    final pts = [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft];
    double sum = 0;
    for (var i = 0; i < 4; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % 4];
      sum += p1.x * p2.y - p2.x * p1.y;
    }
    return sum.abs() / 2.0;
  }

  bool _touchesFrameBorder(CardQuad q, int w, int h, {double marginFrac = 0.015}) {
    final marginX = w * marginFrac;
    final marginY = h * marginFrac;
    for (final p in [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft]) {
      final nearLeftRight = p.x < marginX || p.x > (w - marginX);
      final nearTopBottom = p.y < marginY || p.y > (h - marginY);
      if (!(nearLeftRight || nearTopBottom)) return false;
    }
    return true;
  }

  double _quadScore(CardQuad q, double area, double imageArea) {
    final width = (_dist(q.topLeft, q.topRight) + _dist(q.bottomLeft, q.bottomRight)) / 2.0;
    final height = (_dist(q.topLeft, q.bottomLeft) + _dist(q.topRight, q.bottomRight)) / 2.0;
    if (height == 0) return -1;

    final ratio = width / height;
    final ratioDiff = math.min((ratio - kCardRatio).abs(), ((1 / ratio) - kCardRatio).abs());
    final aspectScore = math.max(0.0, 1 - ratioDiff);

    final ratioArea = area / imageArea;
    const idealArea = 0.30;
    double sizeScore;
    if (ratioArea <= idealArea) {
      sizeScore = ratioArea / idealArea;
    } else {
      sizeScore = math.max(0.0, 1 - (ratioArea - idealArea) / (1 - idealArea));
    }

    return 0.8 * aspectScore + 0.2 * sizeScore;
  }

  cv.Mat _preprocessGray(cv.Mat image) {
    final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    final filtered = cv.bilateralFilter(gray, 9, 75, 75);
    gray.dispose();

    final clahe = cv.createCLAHE(clipLimit: 2.5, tileGridSize: (8, 8));
    final result = clahe.apply(filtered);
    filtered.dispose();

    return result;
  }

  cv.Mat loadTemplateFromBytes(Uint8List bytes) {
    return cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
  }

  (List<_Candidate>, cv.Mat, cv.Mat, cv.Mat, cv.Mat) _findCandidates(
      cv.Mat gray, cv.Mat bgr, double imageArea) {
    final blurred = cv.gaussianBlur(gray, (5, 5), 0);

    final median = _median(gray);
    final lower = math.max(0, (0.66 * median)).toDouble();
    final upper = math.min(255, (1.33 * median)).toDouble();

    final candidates = <_Candidate>[];
    final imgH = gray.rows;
    final imgW = gray.cols;

    final cannyRaw = cv.canny(blurred, lower, upper);
    final edges = cv.dilate(cannyRaw, _kernel5, iterations: 2);
    cannyRaw.dispose();

    final edgesClosed = cv.morphologyEx(edges, cv.MORPH_CLOSE, _kernel15, iterations: 2);
    final edgesClosedFin = cv.morphologyEx(edges, cv.MORPH_CLOSE, _kernel9, iterations: 1);
    edges.dispose();

    _collectCandidatesFromMask(edgesClosed, 'canny', imgW, imgH, imageArea, candidates);
    var bestSoFar = candidates.isEmpty ? 0.0 : candidates.map((c) => c.score).reduce(math.max);

    if (bestSoFar < _earlyExitScore) {
      _collectCandidatesFromMask(edgesClosedFin, 'canny_fin', imgW, imgH, imageArea, candidates);
      bestSoFar = candidates.isEmpty ? 0.0 : candidates.map((c) => c.score).reduce(math.max);
    }

    cv.Mat? threshClosed;
    if (bestSoFar < _earlyExitScore) {
      final thresh = cv.adaptiveThreshold(
        blurred,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY,
        31,
        5,
      );
      threshClosed = cv.morphologyEx(thresh, cv.MORPH_CLOSE, _kernel9);
      thresh.dispose();

      _collectCandidatesFromMask(threshClosed, 'adaptive', imgW, imgH, imageArea, candidates);
      bestSoFar = candidates.isEmpty ? 0.0 : candidates.map((c) => c.score).reduce(math.max);
    }

    cv.Mat? satMask;
    if (bestSoFar < _earlyExitScore) {
      final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
      final channels = cv.split(hsv);
      hsv.dispose();

      final saturation = channels[1];
      channels[0].dispose();
      channels[2].dispose();

      final (_, satMaskRaw) = cv.threshold(saturation, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
      saturation.dispose();
      satMask = cv.morphologyEx(satMaskRaw, cv.MORPH_CLOSE, _kernel15, iterations: 2);
      satMaskRaw.dispose();

      _collectCandidatesFromMask(satMask, 'couleur', imgW, imgH, imageArea, candidates);
    }

    blurred.dispose();

    return (
      candidates,
      edgesClosed,
      edgesClosedFin,
      threshClosed ?? cv.Mat.empty(),
      satMask ?? cv.Mat.empty(),
    );
  }

  void _collectCandidatesFromMask(
    cv.Mat mask,
    String maskName,
    int imgW,
    int imgH,
    double imageArea,
    List<_Candidate> candidates,
  ) {
    final (contours, _) = cv.findContours(mask, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    final sorted = contours.toList()
      ..sort((a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)));
    final top10 = sorted.take(10);

    for (final c in top10) {
      final area = cv.contourArea(c);
      if (area < 0.05 * imageArea) continue;

      final perimeter = cv.arcLength(c, true);
      final approx = cv.approxPolyDP(c, 0.02 * perimeter, true);

      CardQuad quad;
      bool isCleanQuad;
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        final pts = approx.map((p) => cv.Point2f(p.x.toDouble(), p.y.toDouble())).toList();
        quad = _orderPoints(pts);
        isCleanQuad = true;
      } else {
        final rect = cv.minAreaRect(c);
        final box = cv.boxPoints(rect);
        final pts = box.map((p) => cv.Point2f(p.x, p.y)).toList();
        quad = _orderPoints(pts);
        isCleanQuad = false;
      }

      final fittedArea = _quadArea(quad);
      if (fittedArea <= 0) continue;
      if (area / fittedArea < 0.75) continue;

      if (_touchesFrameBorder(quad, imgW, imgH)) continue;

      var score = _quadScore(quad, area, imageArea);
      if (!isCleanQuad) score *= 0.85;

      candidates.add(_Candidate(quad, score, maskName));
    }
  }

  double _median(cv.Mat gray) {
    final (mean, _) = cv.meanStdDev(gray);
    return mean.val1;
  }

  DetectedDocument detectCard(cv.Mat image) {
    const scaleFactor = 1.0;
    final small = cv.resize(image, (0, 0), fx: scaleFactor, fy: scaleFactor);

    final gray = _preprocessGray(small);
    final imageArea = (small.rows * small.cols).toDouble();
    final (candidates, m1, m2, m3, m4) = _findCandidates(gray, small, imageArea);

    small.dispose();
    gray.dispose();
    m1.dispose();
    m2.dispose();
    m3.dispose();
    m4.dispose();

    if (candidates.isEmpty) return DetectedDocument.none();

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;

    if (best.score < kMinScore) return DetectedDocument.none();

    final scaledQuad = CardQuad(
      topLeft: CardPoint(best.quad.topLeft.x / scaleFactor, best.quad.topLeft.y / scaleFactor),
      topRight: CardPoint(best.quad.topRight.x / scaleFactor, best.quad.topRight.y / scaleFactor),
      bottomRight:
          CardPoint(best.quad.bottomRight.x / scaleFactor, best.quad.bottomRight.y / scaleFactor),
      bottomLeft:
          CardPoint(best.quad.bottomLeft.x / scaleFactor, best.quad.bottomLeft.y / scaleFactor),
    );

    return DetectedDocument(
      isDetected: true,
      quad: scaledQuad,
      score: best.score,
      source: best.source,
    );
  }

  cv.Mat warpCard(cv.Mat image, CardQuad quad) {
    final widthTop = _dist(quad.topLeft, quad.topRight);
    final widthBottom = _dist(quad.bottomLeft, quad.bottomRight);
    final heightLeft = _dist(quad.topLeft, quad.bottomLeft);
    final heightRight = _dist(quad.topRight, quad.bottomRight);

    final isLandscape = (widthTop + widthBottom) >= (heightLeft + heightRight);
    final outW = isLandscape ? kOutW : kOutH;
    final outH = isLandscape ? kOutH : kOutW;

    final src = cv.VecPoint.fromList([
      cv.Point(quad.topLeft.x.round(), quad.topLeft.y.round()),
      cv.Point(quad.topRight.x.round(), quad.topRight.y.round()),
      cv.Point(quad.bottomRight.x.round(), quad.bottomRight.y.round()),
      cv.Point(quad.bottomLeft.x.round(), quad.bottomLeft.y.round()),
    ]);
    final dst = cv.VecPoint.fromList([
      cv.Point(0, 0),
      cv.Point(outW - 1, 0),
      cv.Point(outW - 1, outH - 1),
      cv.Point(0, outH - 1),
    ]);

    final m = cv.getPerspectiveTransform(src, dst);
    return cv.warpPerspective(image, m, (outW, outH));
  }

  (PhotoDetectionResult, CardRect?) detectPhotoWithOrientation(cv.Mat warpedCard) {
    if (_faceCascade == null) return (PhotoDetectionResult.none(), null);

    final rotations = <(int, cv.Mat)>[
      (0, warpedCard),
      (90, cv.rotate(warpedCard, cv.ROTATE_90_CLOCKWISE)),
      (180, cv.rotate(warpedCard, cv.ROTATE_180)),
      (270, cv.rotate(warpedCard, cv.ROTATE_90_COUNTERCLOCKWISE)),
    ];

    var bestFound = false;
    var bestAngle = 0;
    var bestConfidence = 0.0;
    CardRect? bestBox;

    for (final (angle, rotated) in rotations) {
      final w = rotated.cols;
      final h = rotated.rows;
      final roiX2 = (w * 0.35).toInt();
      final roiY1 = (h * 0.15).toInt();
      final roi = rotated.region(cv.Rect(0, roiY1, roiX2, h - roiY1));

      final gray = cv.cvtColor(roi, cv.COLOR_BGR2GRAY);
      final minSize = (w * 0.10).toInt();

      final faces = _faceCascade!.detectMultiScale(
        gray,
        scaleFactor: 1.05,
        minNeighbors: 8,
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
    }

    return (
      PhotoDetectionResult(found: bestFound, rotationDegrees: bestAngle, confidence: bestConfidence),
      bestBox,
    );
  }

  cv.Mat loadTemplate(String path) {
    final template = cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
    if (template.isEmpty) {
      throw Exception('Template introuvable : $path');
    }
    return template;
  }

  (bool, double) _matchTemplateInRoi(
      cv.Mat orientedCard, cv.Mat template, cv.Rect roi, {double threshold = 0.6}) {
    final region = orientedCard.region(roi);
    final grayRegion = cv.cvtColor(region, cv.COLOR_BGR2GRAY);

    if (template.rows > grayRegion.rows || template.cols > grayRegion.cols) {
      return (false, 0.0);
    }

    final result = cv.matchTemplate(grayRegion, template, cv.TM_CCOEFF_NORMED);
    final (_, maxVal, _, _) = cv.minMaxLoc(result);

    return (maxVal >= threshold, maxVal);
  }

  (bool, double) detectLogo(cv.Mat orientedCard, cv.Mat templateLogo) {
    final w = orientedCard.cols;
    final h = orientedCard.rows;
    final roi = cv.Rect((w * 0.55).toInt(), 0, (w * 0.45).toInt(), (h * 0.45).toInt());
    return _matchTemplateInRoi(orientedCard, templateLogo, roi);
  }

  (bool, double) detectFlag(cv.Mat orientedCard, cv.Mat templateFlag) {
    final w = orientedCard.cols;
    final h = orientedCard.rows;
    final roi = cv.Rect(0, 0, (w * 0.30).toInt(), (h * 0.40).toInt());
    return _matchTemplateInRoi(orientedCard, templateFlag, roi);
  }

  cv.Mat applyRotation(cv.Mat image, int degrees) {
    switch (degrees) {
      case 90:
        return cv.rotate(image, cv.ROTATE_90_CLOCKWISE);
      case 180:
        return cv.rotate(image, cv.ROTATE_180);
      case 270:
        return cv.rotate(image, cv.ROTATE_90_COUNTERCLOCKWISE);
      default:
        return image;
    }
  }

  (bool, double) detectBarcodePresence(cv.Mat orientedCard) {
    final detector = _barcodeDetector ??= cv.BarcodeDetector.empty();
    final (found, points) = detector.detect(orientedCard);

    if (!found || points.length < 4) return (false, 0.0);

    final cardArea = (orientedCard.rows * orientedCard.cols).toDouble();
    double bestRatio = 0.0;

    for (var i = 0; i + 3 < points.length; i += 4) {
      final quad = [points[i], points[i + 1], points[i + 2], points[i + 3]];
      double area = 0;
      for (var j = 0; j < 4; j++) {
        final p1 = quad[j];
        final p2 = quad[(j + 1) % 4];
        area += p1.x * p2.y - p2.x * p1.y;
      }
      area = area.abs() / 2.0;

      final ratio = area / cardArea;
      if (ratio > bestRatio) bestRatio = ratio;
    }

    return (bestRatio > 0, bestRatio);
  }

  void disposeBarcodeDetector() {
    _barcodeDetector?.dispose();
    _barcodeDetector = null;
  }

  static const double kFingerprintRoiX1 = 0.55;
  static const double kFingerprintRoiY1 = 0.55;
  static const double kFingerprintRoiX2 = 0.95;
  static const double kFingerprintRoiY2 = 0.95;

  (bool, double) detectFingerprintPresence(
    cv.Mat orientedCard, {
    double minVariance = 150,
    double maxVariance = 4000,
  }) {
    final gray = cv.cvtColor(orientedCard, cv.COLOR_BGR2GRAY);
    final w = gray.cols;
    final h = gray.rows;

    final roi = gray.region(cv.Rect(
      (kFingerprintRoiX1 * w).toInt(),
      (kFingerprintRoiY1 * h).toInt(),
      ((kFingerprintRoiX2 - kFingerprintRoiX1) * w).toInt(),
      ((kFingerprintRoiY2 - kFingerprintRoiY1) * h).toInt(),
    ));

    final laplacian = cv.laplacian(roi, cv.MatType.CV_64F);
    final (_, stddev) = cv.meanStdDev(laplacian);
    final variance = stddev.val1 * stddev.val1;

    final found = variance >= minVariance && variance <= maxVariance;
    return (found, variance);
  }

  (bool, (int, int, int, int)?, double) detectSeparationLine(
    cv.Mat orientedCard, {
    double minLengthRatio = 0.5,
  }) {
    final w = orientedCard.cols;

    // --- Signal couleur : capture les transitions rose -> blanc que Canny
    // sur le gris rate, car la luminosite est quasi identique des deux cotes.
    final hsv = cv.cvtColor(orientedCard, cv.COLOR_BGR2HSV);
    final channels = cv.split(hsv);
    hsv.dispose();
    final saturation = channels[1];
    channels[0].dispose(); // hue, inutile ici
    channels[2].dispose(); // value, inutile ici

    final blurredSat = cv.gaussianBlur(saturation, (5, 5), 0);
    saturation.dispose();

    // Sobel vertical (dy) : une ligne horizontale = un changement brutal de
    // saturation le long de l'axe Y, donc un fort gradient dy a cet endroit.
    final gradY = cv.sobel(blurredSat, cv.MatType.CV_32F, 0, 1, ksize: 3);
    blurredSat.dispose();
    final absGradY = cv.convertScaleAbs(gradY);
    gradY.dispose();

    final (_, colorEdges) = cv.threshold(absGradY, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
    absGradY.dispose();

    // --- Signal luminosite classique en complement, pour les cartes ou la
    // ligne EST un vrai contraste clair/fonce ---
    final gray = cv.cvtColor(orientedCard, cv.COLOR_BGR2GRAY);
    final grayEdges = cv.canny(gray, 50, 150);
    gray.dispose();

    // Combine les deux signaux -- une ligne detectee par l'un OU l'autre compte
    final edges = cv.bitwiseOR(colorEdges, grayEdges);
    colorEdges.dispose();
    grayEdges.dispose();

    final linesMat = cv.HoughLinesP(
      edges,
      1,
      3.14159265 / 180,
      80,
      minLineLength: (w * minLengthRatio).toDouble(),
      maxLineGap: 10,
    );
    edges.dispose();

    (int, int, int, int)? bestLine;
    double bestLength = 0;

    final linesList = linesMat.toList();
    linesMat.dispose();

    for (final line in linesList) {
      final x1 = (line[0]).toInt();
      final y1 = (line[1]).toInt();
      final x2 = (line[2]).toInt();
      final y2 = (line[3]).toInt();

      final dx = (x2 - x1).toDouble();
      final dy = (y2 - y1).toDouble();
      final length = math.sqrt(dx * dx + dy * dy);

      final angle = (math.atan2(dy, dx) * 180 / math.pi).abs();
      final isHorizontal = angle < 10 || angle > 170;

      if (isHorizontal && length > bestLength) {
        bestLength = length;
        bestLine = (x1, y1, x2, y2);
      }
    }

    if (bestLine == null) return (false, null, 0.0);

    final lengthRatio = bestLength / w;
    final found = lengthRatio >= minLengthRatio;
    return (found, bestLine, lengthRatio);
  }
}