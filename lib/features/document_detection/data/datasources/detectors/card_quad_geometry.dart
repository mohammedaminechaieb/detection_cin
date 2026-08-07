import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../domain/entities/detected_document.dart';

/// The physical aspect ratio (width / height) of a Tunisian national ID
/// card, used to score how "card-like" a detected quad is.
const double kCardAspectRatio = 85.6 / 54.0;

/// Pure geometry helpers for scoring and normalizing a detected card quad.
/// Contains no OpenCV Mat state, so it's trivial to unit test.
class CardQuadGeometry {
  const CardQuadGeometry();

  /// Orders four unordered corner points into (topLeft, topRight,
  /// bottomRight, bottomLeft) using the standard sum/diff trick:
  /// top-left has the smallest x+y, bottom-right the largest; top-right
  /// has the smallest y-x, bottom-left the largest.
  CardQuad orderPoints(List<cv.Point2f> pts) {
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

  double distance(CardPoint a, CardPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  double quadArea(CardQuad q) {
    final pts = [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft];
    double sum = 0;
    for (var i = 0; i < 4; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % 4];
      sum += p1.x * p2.y - p2.x * p1.y;
    }
    return sum.abs() / 2.0;
  }

  bool touchesFrameBorder(CardQuad q, int w, int h, {double marginFrac = 0.015}) {
    final marginX = w * marginFrac;
    final marginY = h * marginFrac;
    for (final p in [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft]) {
      final nearLeftRight = p.x < marginX || p.x > (w - marginX);
      final nearTopBottom = p.y < marginY || p.y > (h - marginY);
      if (!(nearLeftRight || nearTopBottom)) return false;
    }
    return true;
  }

  /// Scores how "card-like" [q] is: 80% based on how close its aspect
  /// ratio is to [kCardAspectRatio], 20% based on how close its area is
  /// to the ideal fraction of the image it should occupy.
  double quadScore(CardQuad q, double area, double imageArea) {
    final width = (distance(q.topLeft, q.topRight) + distance(q.bottomLeft, q.bottomRight)) / 2.0;
    final height = (distance(q.topLeft, q.bottomLeft) + distance(q.topRight, q.bottomRight)) / 2.0;
    if (height == 0) return -1;

    final ratio = width / height;
    final ratioDiff =
        math.min((ratio - kCardAspectRatio).abs(), ((1 / ratio) - kCardAspectRatio).abs());
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
}
