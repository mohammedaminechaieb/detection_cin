import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'package:detection_cin/features/document_detection/data/datasources/detectors/card_quad_geometry.dart';
import 'package:detection_cin/features/document_detection/domain/entities/detected_document.dart';

void main() {
  group('CardQuadGeometry', () {
    const geometry = CardQuadGeometry();

    group('orderPoints', () {
      test('orders 4 axis-aligned points into TL, TR, BR, BL regardless of input order', () {
        // A 100x50 rectangle at origin, deliberately shuffled.
        final shuffled = [
          cv.Point2f(100, 50), // bottom-right
          cv.Point2f(0, 0), // top-left
          cv.Point2f(100, 0), // top-right
          cv.Point2f(0, 50), // bottom-left
        ];

        final quad = geometry.orderPoints(shuffled);

        expect(quad.topLeft.x, 0);
        expect(quad.topLeft.y, 0);
        expect(quad.topRight.x, 100);
        expect(quad.topRight.y, 0);
        expect(quad.bottomRight.x, 100);
        expect(quad.bottomRight.y, 50);
        expect(quad.bottomLeft.x, 0);
        expect(quad.bottomLeft.y, 50);
      });

      test('orders a rotated/skewed quad using the sum/diff heuristic', () {
        // A quad tilted slightly - still clearly TL/TR/BR/BL by
        // position, just not axis-aligned.
        final pts = [
          cv.Point2f(10, 5), // top-left-ish
          cv.Point2f(110, 0), // top-right-ish
          cv.Point2f(120, 60), // bottom-right-ish
          cv.Point2f(0, 55), // bottom-left-ish
        ];

        final quad = geometry.orderPoints(pts);

        expect(quad.topLeft.x, 10);
        expect(quad.topRight.x, 110);
        expect(quad.bottomRight.x, 120);
        expect(quad.bottomLeft.x, 0);
      });
    });

    test('distance computes Euclidean distance between two points', () {
      expect(geometry.distance(const CardPoint(0, 0), const CardPoint(3, 4)), 5.0);
      expect(geometry.distance(const CardPoint(1, 1), const CardPoint(1, 1)), 0.0);
    });

    test('quadArea computes area of an axis-aligned rectangle', () {
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(100, 0),
        bottomRight: CardPoint(100, 50),
        bottomLeft: CardPoint(0, 50),
      );
      expect(geometry.quadArea(quad), 5000.0);
    });

    group('touchesFrameBorder', () {
      test('returns true when every corner is within the margin of an edge', () {
        // A thin sliver hugging the left edge of a 200x100 frame.
        const quad = CardQuad(
          topLeft: CardPoint(0, 0),
          topRight: CardPoint(1, 0),
          bottomRight: CardPoint(1, 99),
          bottomLeft: CardPoint(0, 99),
        );
        expect(geometry.touchesFrameBorder(quad, 200, 100), isTrue);
      });

      test('returns false for a quad comfortably inside the frame', () {
        const quad = CardQuad(
          topLeft: CardPoint(50, 30),
          topRight: CardPoint(150, 30),
          bottomRight: CardPoint(150, 70),
          bottomLeft: CardPoint(50, 70),
        );
        expect(geometry.touchesFrameBorder(quad, 200, 100), isFalse);
      });
    });

    group('quadScore', () {
      test('scores highest for a quad matching the card aspect ratio at the ideal area fraction', () {
        // width/height == kCardAspectRatio, area == 30% of the image
        // (the "ideal" fraction quadScore targets) -> should score
        // very close to the maximum of 1.0.
        const imageArea = 1000.0;
        const area = 0.30 * imageArea;
        final height = 20.0;
        final width = height * kCardAspectRatio;
        final quad = CardQuad(
          topLeft: const CardPoint(0, 0),
          topRight: CardPoint(width, 0),
          bottomRight: CardPoint(width, height),
          bottomLeft: CardPoint(0, height),
        );

        final score = geometry.quadScore(quad, area, imageArea);
        expect(score, closeTo(1.0, 0.01));
      });

      test('scores lower for a near-square quad (wrong aspect ratio)', () {
        const imageArea = 1000.0;
        const quad = CardQuad(
          topLeft: CardPoint(0, 0),
          topRight: CardPoint(50, 0),
          bottomRight: CardPoint(50, 50),
          bottomLeft: CardPoint(0, 50),
        );
        final area = 50.0 * 50.0;

        final aspectMatched = geometry.quadScore(
          CardQuad(
            topLeft: const CardPoint(0, 0),
            topRight: CardPoint(50 * kCardAspectRatio, 0),
            bottomRight: CardPoint(50 * kCardAspectRatio, 50),
            bottomLeft: CardPoint(0, 50),
          ),
          50 * kCardAspectRatio * 50,
          imageArea,
        );
        final square = geometry.quadScore(quad, area, imageArea);

        expect(square, lessThan(aspectMatched));
      });

      test('returns -1 for a degenerate zero-height quad', () {
        const quad = CardQuad(
          topLeft: CardPoint(0, 0),
          topRight: CardPoint(100, 0),
          bottomRight: CardPoint(100, 0),
          bottomLeft: CardPoint(0, 0),
        );
        expect(geometry.quadScore(quad, 0, 1000), -1);
      });
    });
  });
}
