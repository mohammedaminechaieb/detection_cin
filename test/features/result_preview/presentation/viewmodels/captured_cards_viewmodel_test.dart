// Tier A - pure Dart/Flutter ChangeNotifier, no mocks, no platform.
// See test/README.md.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/document_detection/domain/entities/detected_document.dart' show CardSide;
import 'package:detection_cin/features/result_preview/presentation/viewmodels/captured_cards_viewmodel.dart';

void main() {
  group('CapturedCardsViewModel', () {
    test('starts empty and incomplete', () {
      final vm = CapturedCardsViewModel();
      expect(vm.card.front, isNull);
      expect(vm.card.back, isNull);
      expect(vm.isComplete, isFalse);
    });

    test('setCapture(front, ...) sets only the front side', () {
      final vm = CapturedCardsViewModel();
      final bytes = Uint8List.fromList([1, 2, 3]);
      vm.setCapture(CardSide.front, bytes);

      expect(vm.card.front, same(bytes));
      expect(vm.card.back, isNull);
      expect(vm.isComplete, isFalse);
    });

    test('setting both sides makes isComplete true', () {
      final vm = CapturedCardsViewModel();
      vm.setCapture(CardSide.front, Uint8List.fromList([1]));
      vm.setCapture(CardSide.back, Uint8List.fromList([2]));
      expect(vm.isComplete, isTrue);
    });

    test('setCapture notifies listeners', () {
      final vm = CapturedCardsViewModel();
      var notified = 0;
      vm.addListener(() => notified++);
      vm.setCapture(CardSide.front, Uint8List.fromList([1]));
      expect(notified, 1);
    });

    test('setCapture(front) again overwrites the previous front without touching back', () {
      final vm = CapturedCardsViewModel();
      vm.setCapture(CardSide.back, Uint8List.fromList([9]));
      vm.setCapture(CardSide.front, Uint8List.fromList([1]));
      vm.setCapture(CardSide.front, Uint8List.fromList([2]));

      expect(vm.card.front, Uint8List.fromList([2]));
      expect(vm.card.back, Uint8List.fromList([9]));
    });

    test('reset() clears both sides and notifies', () {
      final vm = CapturedCardsViewModel();
      vm.setCapture(CardSide.front, Uint8List.fromList([1]));
      vm.setCapture(CardSide.back, Uint8List.fromList([2]));
      expect(vm.isComplete, isTrue);

      var notified = 0;
      vm.addListener(() => notified++);
      vm.reset();

      expect(vm.card.front, isNull);
      expect(vm.card.back, isNull);
      expect(vm.isComplete, isFalse);
      expect(notified, 1);
    });
  });
}
