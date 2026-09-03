// Tier A - uses real Flutter compute() isolates but only pure-Dart
// (package:image) work inside them, so this runs anywhere `flutter test`
// runs, no platform channels or native libs involved. See test/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:detection_cin/features/image_postprocessing/domain/entities/enhancement_settings.dart';
import 'package:detection_cin/features/image_postprocessing/presentation/viewmodels/postprocessing_viewmodel.dart';

import '../../../../test_helpers/png_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PostprocessingViewModel', () {
    test('process() publishes enhanced front/back before the print page is ready, then fills printPage in', () async {
      final vm = PostprocessingViewModel();
      final events = <bool>[]; // isProcessing snapshots via listener
      vm.addListener(() => events.add(vm.isProcessing));

      final future = vm.process(checkerPng(), checkerPng());

      // Immediately after calling process() (before awaiting), isProcessing
      // should already be true and a notification should have fired.
      expect(vm.isProcessing, isTrue);

      await future;

      expect(vm.isProcessing, isFalse);
      expect(vm.error, isNull);
      expect(vm.result, isNotNull);
      expect(vm.result!.front, isNotEmpty);
      expect(vm.result!.back, isNotEmpty);

      // print page composition is fire-and-forget from process()'s point of
      // view; wait for it to settle before asserting on it.
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return vm.isComposingPrintPage;
      }).timeout(const Duration(seconds: 10));

      expect(vm.result!.printPage, isNotNull);
      expect(vm.printPageError, isNull);
    });

    test('settings passed to process() are stored and reused on subsequent calls without new settings', () async {
      final vm = PostprocessingViewModel();
      await vm.process(
        checkerPng(),
        checkerPng(),
        settings: const EnhancementSettings(grayscale: true),
      );
      expect(vm.settings.grayscale, isTrue);
    });

    test('reset() clears result/error/settings back to defaults', () async {
      final vm = PostprocessingViewModel();
      await vm.process(checkerPng(), checkerPng(), settings: const EnhancementSettings(grayscale: true));
      expect(vm.result, isNotNull);

      vm.reset();
      expect(vm.result, isNull);
      expect(vm.error, isNull);
      expect(vm.printPageError, isNull);
      expect(vm.isProcessing, isFalse);
      expect(vm.isComposingPrintPage, isFalse);
      expect(vm.settings.grayscale, isFalse);
    });

    test('undecodable input: enhancement step succeeds (passthrough), print-page composition fails cleanly', () async {
      final vm = PostprocessingViewModel();
      await vm.process(garbageBytes(), garbageBytes());

      // CardImageEnhancer returns undecodable input unchanged rather than
      // throwing, so process() itself reports no error and isProcessing
      // settles to false.
      expect(vm.isProcessing, isFalse);
      expect(vm.error, isNull);
      expect(vm.result, isNotNull);

      // Downstream print-page composition requires decodable PNGs and will
      // fail (PrintPageComposer.compose throws StateError) - that failure
      // must surface as printPageError, not crash the app or hang
      // isComposingPrintPage forever.
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return vm.isComposingPrintPage;
      }).timeout(const Duration(seconds: 10));

      expect(vm.printPageError, isNotNull);
      expect(vm.result!.printPage, isNull);
    });
  });
}
