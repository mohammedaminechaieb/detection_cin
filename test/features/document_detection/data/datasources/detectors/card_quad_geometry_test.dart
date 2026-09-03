// Tier C - needs opencv_dart's native binary (for cv.Point2f), no device
// required, no image fixtures (synthetic points only). See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:detection_cin/features/document_detection/data/datasources/detectors/card_quad_geometry.dart';
import 'package:detection_cin/features/document_detection/domain/entities/detected_document.dart';

void main() {
  const geometry = CardQuadGeometry();

  group('CardQuadGeometry.orderPoints', () {
    test('orders four scrambled points into TL, TR, BR, BL', () {
      // A 100x60 rectangle at origin, deliberately shuffled.
      final pts = [
        cv.Point2f(100, 60), // BR
        cv.Point2f(0, 0), // TL
        cv.Point2f(100, 0), // TR
        cv.Point2f(0, 60), // BL
      ];
      final quad = geometry.orderPoints(pts);

      expect(quad.topLeft.x, 0);
      expect(quad.topLeft.y, 0);
      expect(quad.topRight.x, 100);
      expect(quad.topRight.y, 0);
      expect(quad.bottomRight.x, 100);
      expect(quad.bottomRight.y, 60);
      expect(quad.bottomLeft.x, 0);
      expect(quad.bottomLeft.y, 60);
    });

    test('already-ordered points remain in the same order', () {
      final pts = [
        cv.Point2f(0, 0),
        cv.Point2f(50, 0),
        cv.Point2f(50, 50),
        cv.Point2f(0, 50),
      ];
      final quad = geometry.orderPoints(pts);
      expect(quad.topLeft.x, 0);
      expect(quad.topLeft.y, 0);
      expect(quad.bottomRight.x, 50);
      expect(quad.bottomRight.y, 50);
    });
  });

  group('CardQuadGeometry.distance', () {
    test('computes Euclidean distance between two points', () {
      expect(geometry.distance(const CardPoint(0, 0), const CardPoint(3, 4)), 5.0);
    });

    test('distance from a point to itself is 0', () {
      const p = CardPoint(10, 10);
      expect(geometry.distance(p, p), 0.0);
    });
  });

  group('CardQuadGeometry.quadArea', () {
    test('computes area of an axis-aligned rectangle via the shoelace formula', () {
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(100, 0),
        bottomRight: CardPoint(100, 50),
        bottomLeft: CardPoint(0, 50),
      );
      expect(geometry.quadArea(quad), 5000.0);
    });
  });

  group('CardQuadGeometry.touchesFrameBorder', () {
    test('a quad fully inside the frame with margin does not touch the border', () {
      const quad = CardQuad(
        topLeft: CardPoint(50, 50),
        topRight: CardPoint(150, 50),
        bottomRight: CardPoint(150, 150),
        bottomLeft: CardPoint(50, 150),
      );
      expect(geometry.touchesFrameBorder(quad, 400, 400), isFalse);
    });

    test('a quad with corners at the frame edges touches the border', () {
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(400, 0),
        bottomRight: CardPoint(400, 400),
        bottomLeft: CardPoint(0, 400),
      );
      expect(geometry.touchesFrameBorder(quad, 400, 400), isTrue);
    });
  });

  group('CardQuadGeometry.insetQuad', () {
    test('insetFraction 0 returns the same coordinates (no shrink)', () {
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(100, 0),
        bottomRight: CardPoint(100, 100),
        bottomLeft: CardPoint(0, 100),
      );
      final result = geometry.insetQuad(quad, 0.0);
      expect(result.topLeft.x, closeTo(0, 1e-9));
      expect(result.bottomRight.x, closeTo(100, 1e-9));
    });

    test('insetFraction 1.0 collapses all corners to the centroid', () {
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(100, 0),
        bottomRight: CardPoint(100, 100),
        bottomLeft: CardPoint(0, 100),
      );
      final result = geometry.insetQuad(quad, 1.0);
      for (final p in [result.topLeft, result.topRight, result.bottomRight, result.bottomLeft]) {
        expect(p.x, closeTo(50, 1e-9));
        expect(p.y, closeTo(50, 1e-9));
      }
    });

    test('partial inset moves each corner toward the centroid', () {
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(100, 0),
        bottomRight: CardPoint(100, 100),
        bottomLeft: CardPoint(0, 100),
      );
      final result = geometry.insetQuad(quad, 0.1);
      expect(result.topLeft.x, greaterThan(0));
      expect(result.topLeft.y, greaterThan(0));
      expect(result.bottomRight.x, lessThan(100));
      expect(result.bottomRight.y, lessThan(100));
    });
  });

  group('CardQuadGeometry.quadScore', () {
    test('a quad at exactly kCardAspectRatio and ideal area fraction scores near 1.0', () {
      const imageArea = 10000.0;
      const targetArea = imageArea * 0.30; // idealArea from the implementation
      final height = 100.0;
      final width = height * kCardAspectRatio;
      final quad = CardQuad(
        topLeft: const CardPoint(0, 0),
        topRight: CardPoint(width, 0),
        bottomRight: CardPoint(width, height),
        bottomLeft: CardPoint(0, height),
      );
      final score = geometry.quadScore(quad, targetArea, imageArea);
      expect(score, closeTo(1.0, 0.02));
    });

    test('a square (aspect ratio 1.0, far from card ratio) scores lower than an ideal card', () {
      const imageArea = 10000.0;
      const square = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(80, 0),
        bottomRight: CardPoint(80, 80),
        bottomLeft: CardPoint(0, 80),
      );
      final height = 100.0;
      final width = height * kCardAspectRatio;
      final idealCard = CardQuad(
        topLeft: const CardPoint(0, 0),
        topRight: CardPoint(width, 0),
        bottomRight: CardPoint(width, height),
        bottomLeft: CardPoint(0, height),
      );

      final squareScore = geometry.quadScore(square, 80.0 * 80.0, imageArea);
      final cardScore = geometry.quadScore(idealCard, width * height, imageArea);
      expect(squareScore, lessThan(cardScore));
    });

    test('a degenerate zero-height quad returns -1 rather than dividing by zero', () {
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(100, 0),
        bottomRight: CardPoint(100, 0),
        bottomLeft: CardPoint(0, 0),
      );
      expect(geometry.quadScore(quad, 0, 10000), -1);
    });
  });
}
