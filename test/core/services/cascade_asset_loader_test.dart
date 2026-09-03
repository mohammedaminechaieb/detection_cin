// Tier B - swaps PathProviderPlatform.instance for a fake temp dir and
// mocks the asset-bundle binary messenger channel so rootBundle.load()
// returns synthetic bytes instead of needing the app's real bundled
// asset. Runs anywhere, no device. See test/README.md.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:detection_cin/core/services/cascade_asset_loader.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final fakeCascadeBytes = Uint8List.fromList(List.generate(64, (i) => i % 256));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cascade_loader_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        return ByteData.sublistView(fakeCascadeBytes);
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes the asset bytes to a file under the temp directory and returns its path', () async {
    final path = await loadCascadeAssetPath();
    expect(path, '${tempDir.path}/haarcascade_frontalface_default.xml');

    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), fakeCascadeBytes);
  });

  test('does not re-read the asset bundle if the file already exists on disk', () async {
    // First call creates the file.
    final firstPath = await loadCascadeAssetPath();
    // Corrupt the file on disk directly to prove a second call reuses it
    // rather than re-fetching from the (mocked) bundle.
    await File(firstPath).writeAsBytes(Uint8List.fromList([9, 9, 9]));

    final secondPath = await loadCascadeAssetPath();
    expect(secondPath, firstPath);
    expect(await File(secondPath).readAsBytes(), [9, 9, 9], reason: 'second call must not overwrite an existing file');
  });

  test('honors custom assetPath/fileName parameters', () async {
    final path = await loadCascadeAssetPath(assetPath: 'assets/other.xml', fileName: 'other.xml');
    expect(path, '${tempDir.path}/other.xml');
    expect(await File(path).exists(), isTrue);
  });
}
