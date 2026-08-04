import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';




Future<String> loadCascadeAssetPath({
  String assetPath = 'assets/haarcascade_frontalface_default.xml',
  String fileName = 'haarcascade_frontalface_default.xml',
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');

  if (!await file.exists()) {
    final bytes = await rootBundle.load(assetPath);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  return file.path;
}
