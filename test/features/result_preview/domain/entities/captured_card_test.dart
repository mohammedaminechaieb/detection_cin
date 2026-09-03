// Tier A - pure Dart entity, no mocks, no platform. See test/README.md.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/result_preview/domain/entities/captured_card.dart';

void main() {
  group('CapturedCard', () {
    test('default constructor has null front/back and isComplete false', () {
      const card = CapturedCard();
      expect(card.front, isNull);
      expect(card.back, isNull);
      expect(card.isComplete, isFalse);
    });

    test('isComplete is true only when both front and back are set', () {
      final front = Uint8List.fromList([1]);
      final back = Uint8List.fromList([2]);

      expect(CapturedCard(front: front).isComplete, isFalse);
      expect(CapturedCard(back: back).isComplete, isFalse);
      expect(CapturedCard(front: front, back: back).isComplete, isTrue);
    });

    test('copyWith sets front without disturbing an existing back', () {
      final back = Uint8List.fromList([9]);
      const card = CapturedCard();
      final withBack = card.copyWith(back: back);
      final withFrontToo = withBack.copyWith(front: Uint8List.fromList([1]));

      expect(withFrontToo.back, same(back));
      expect(withFrontToo.isComplete, isTrue);
    });

    test('copyWith() with no args preserves existing values', () {
      final front = Uint8List.fromList([1]);
      final back = Uint8List.fromList([2]);
      final card = CapturedCard(front: front, back: back);
      final copy = card.copyWith();
      expect(copy.front, same(front));
      expect(copy.back, same(back));
    });
  });
}
