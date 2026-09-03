// Tier A - pure Dart entity, no mocks, no platform. See test/README.md.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/image_postprocessing/domain/entities/processed_card.dart';

void main() {
  group('ProcessedCard', () {
    test('printPage defaults to null', () {
      final card = ProcessedCard(front: Uint8List(0), back: Uint8List(0));
      expect(card.printPage, isNull);
    });

    test('copyWith(printPage: x) sets printPage and preserves front/back', () {
      final front = Uint8List.fromList([1, 2, 3]);
      final back = Uint8List.fromList([4, 5, 6]);
      final printPage = Uint8List.fromList([7, 8]);
      final card = ProcessedCard(front: front, back: back);

      final updated = card.copyWith(printPage: printPage);
      expect(updated.front, same(front));
      expect(updated.back, same(back));
      expect(updated.printPage, same(printPage));
    });

    test('copyWith() with no args preserves an already-set printPage', () {
      final printPage = Uint8List.fromList([9]);
      final card = ProcessedCard(front: Uint8List(0), back: Uint8List(0), printPage: printPage);
      final updated = card.copyWith();
      expect(updated.printPage, same(printPage));
    });
  });
}
