import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../domain/entities/detected_document.dart';
import 'card_quad_geometry.dart';

/// Output resolution (in pixels) for a warped card image, in landscape
/// orientation. Chosen to preserve [kCardAspectRatio] at a resolution
/// that's sharp enough for downstream template/face/barcode matching.
const int kWarpedCardWidth = 856;
const int kWarpedCardHeight = 540;

/// Rectifies a detected card quad into a flat, top-down image via a
/// perspective transform.
class PerspectiveWarper {
  PerspectiveWarper({CardQuadGeometry? geometry}) : _geometry = geometry ?? const CardQuadGeometry();

  final CardQuadGeometry _geometry;

  /// Warps the region of [image] bounded by [quad] into a
  /// [kWarpedCardWidth] x [kWarpedCardHeight] (or transposed, if the
  /// quad is portrait-oriented) rectified image.
  cv.Mat warp(cv.Mat image, CardQuad quad) {
    final widthTop = _geometry.distance(quad.topLeft, quad.topRight);
    final widthBottom = _geometry.distance(quad.bottomLeft, quad.bottomRight);
    final heightLeft = _geometry.distance(quad.topLeft, quad.bottomLeft);
    final heightRight = _geometry.distance(quad.topRight, quad.bottomRight);

    final isLandscape = (widthTop + widthBottom) >= (heightLeft + heightRight);
    final outW = isLandscape ? kWarpedCardWidth : kWarpedCardHeight;
    final outH = isLandscape ? kWarpedCardHeight : kWarpedCardWidth;

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

    final transform = cv.getPerspectiveTransform(src, dst);
    final warped = cv.warpPerspective(image, transform, (outW, outH));
    transform.dispose();

    return warped;
  }
}
