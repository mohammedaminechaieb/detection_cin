// Tier C - needs opencv_dart's native binary, no device required, uses
// synthetic in-memory Mats. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/document_detection/data/datasources/detectors/perspective_warper.dart';
import 'package:detection_cin/features/document_detection/domain/entities/detected_document.dart';

import '../../../../../test_helpers/mat_test_utils.dart';

void main() {
  final warper = PerspectiveWarper();

  group('PerspectiveWarper.warp', () {
    test('a landscape-oriented quad produces a kWarpedCardWidth x kWarpedCardHeight output', () {
      final frame = syntheticCardMat(width: 1000, height: 700);
      // A landscape quad (wider than tall) roughly matching the card
      // drawn by syntheticCardMat.
      const quad = CardQuad(
        topLeft: CardPoint(100, 70),
        topRight: CardPoint(900, 70),
        bottomRight: CardPoint(900, 630),
        bottomLeft: CardPoint(100, 630),
      );

      final warped = warper.warp(frame, quad);
      expect(warped.cols, kWarpedCardWidth);
      expect(warped.rows, kWarpedCardHeight);
      disposeAll([frame, warped]);
    });

    test('a portrait-oriented quad transposes the output dimensions', () {
      final frame = syntheticCardMat(width: 700, height: 1000);
      const quad = CardQuad(
        topLeft: CardPoint(70, 100),
        topRight: CardPoint(630, 100),
        bottomRight: CardPoint(630, 900),
        bottomLeft: CardPoint(70, 900),
      );

      final warped = warper.warp(frame, quad);
      expect(warped.cols, kWarpedCardHeight);
      expect(warped.rows, kWarpedCardWidth);
      disposeAll([frame, warped]);
    });

    test('output Mat always has the same channel count as the input', () {
      final frame = syntheticCardMat(width: 800, height: 500);
      const quad = CardQuad(
        topLeft: CardPoint(0, 0),
        topRight: CardPoint(800, 0),
        bottomRight: CardPoint(800, 500),
        bottomLeft: CardPoint(0, 500),
      );
      final warped = warper.warp(frame, quad);
      expect(warped.channels, frame.channels);
      disposeAll([frame, warped]);
    });
  });
}
