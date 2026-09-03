// Tier B - swaps PathProviderPlatform.instance for a fake pointing at a
// real OS temp directory (created/torn down per test), so file I/O is
// real but there's no dependency on the app being installed on a
// device. `package:gal` calls (saveToGallery) are NOT covered here -
// gal has no swappable platform-interface the way path_provider does,
// so exercising it needs either a real device/emulator or a raw
// MethodChannel mock of gal's native channel (channel name unverified);
// see integration_test/capture_storage_gal_export_test.dart (Tier D).
// See test/README.md.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:detection_cin/core/services/capture_storage_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const service = CaptureStorageService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('capture_storage_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Uint8List bytes(int seed) => Uint8List.fromList(List.generate(16, (i) => (i + seed) % 256));

  // CaptureStorageService.save() builds `directory` by string
  // interpolation (always '/'), while listCaptures() derives it from
  // Directory.list() entities, whose .path Dart normalizes to the
  // platform separator ('\' on Windows). Both point at the same folder
  // on disk, but a strict string comparison between the two would fail
  // on Windows on that separator alone - normalize before comparing.
  String norm(String path) => path.replaceAll('\\', '/');

  group('CaptureStorageService.save', () {
    test('writes all five expected files under captures/<timestamp>/', () async {
      final saved = await service.save(
        rawFront: bytes(1),
        rawBack: bytes(2),
        enhancedFront: bytes(3),
        enhancedBack: bytes(4),
        printPage: bytes(5),
      );

      expect(await File('${saved.directory}/front_raw.png').exists(), isTrue);
      expect(await File('${saved.directory}/back_raw.png').exists(), isTrue);
      expect(await File(saved.frontPath).exists(), isTrue);
      expect(await File(saved.backPath).exists(), isTrue);
      expect(await File(saved.printPagePath).exists(), isTrue);
      expect(saved.frontPath, endsWith('front_enhanced.png'));
      expect(saved.backPath, endsWith('back_enhanced.png'));
    });

    test('written bytes round-trip exactly', () async {
      final saved = await service.save(
        rawFront: bytes(1),
        rawBack: bytes(2),
        enhancedFront: bytes(3),
        enhancedBack: bytes(4),
        printPage: bytes(5),
      );
      expect(await File(saved.frontPath).readAsBytes(), bytes(3));
      expect(await File(saved.printPagePath).readAsBytes(), bytes(5));
    });

    test('two saves in the same test produce different, sortable timestamp folders', () async {
      final first = await service.save(
        rawFront: bytes(1),
        rawBack: bytes(2),
        enhancedFront: bytes(3),
        enhancedBack: bytes(4),
        printPage: bytes(5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await service.save(
        rawFront: bytes(1),
        rawBack: bytes(2),
        enhancedFront: bytes(3),
        enhancedBack: bytes(4),
        printPage: bytes(5),
      );

      expect(first.directory, isNot(equals(second.directory)));
    });
  });

  group('CaptureStorageService.listCaptures', () {
    test('returns an empty list when no captures/ directory exists yet', () async {
      expect(await service.listCaptures(), isEmpty);
    });

    test('lists a saved capture, newest first', () async {
      final first = await service.save(
        rawFront: bytes(1),
        rawBack: bytes(2),
        enhancedFront: bytes(3),
        enhancedBack: bytes(4),
        printPage: bytes(5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await service.save(
        rawFront: bytes(1),
        rawBack: bytes(2),
        enhancedFront: bytes(3),
        enhancedBack: bytes(4),
        printPage: bytes(5),
      );

      final list = await service.listCaptures();
      expect(list.length, 2);
      expect(norm(list.first.directory), norm(second.directory), reason: 'newest first');
      expect(norm(list.last.directory), norm(first.directory));
    });

    test('skips a capture folder missing its enhanced images (mid-write / tampered)', () async {
      final capturesDir = Directory('${tempDir.path}/captures/20260101_010101001');
      await capturesDir.create(recursive: true);
      // Only write the raw files, not the enhanced ones listCaptures requires.
      await File('${capturesDir.path}/front_raw.png').writeAsBytes(bytes(1));

      expect(await service.listCaptures(), isEmpty);
    });

    test('skips folders whose name does not match the timestamp pattern', () async {
      final badDir = Directory('${tempDir.path}/captures/not_a_timestamp');
      await badDir.create(recursive: true);
      await File('${badDir.path}/front_enhanced.png').writeAsBytes(bytes(1));
      await File('${badDir.path}/back_enhanced.png').writeAsBytes(bytes(2));

      expect(await service.listCaptures(), isEmpty);
    });
  });

  group('CaptureStorageService.deleteCapture', () {
    test('removes the folder and its contents', () async {
      final saved = await service.save(
        rawFront: bytes(1),
        rawBack: bytes(2),
        enhancedFront: bytes(3),
        enhancedBack: bytes(4),
        printPage: bytes(5),
      );
      expect(await Directory(saved.directory).exists(), isTrue);

      await service.deleteCapture(saved.directory);
      expect(await Directory(saved.directory).exists(), isFalse);
    });

    test('deleting a non-existent directory does not throw', () async {
      await expectLater(service.deleteCapture('${tempDir.path}/does_not_exist'), completes);
    });
  });
}
