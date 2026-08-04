import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'app.dart';
import 'core/services/cascade_asset_loader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cascadePath = await loadCascadeAssetPath();

  final logoData = await rootBundle.load('assets/templates/logo.png');
  final flagData = await rootBundle.load('assets/templates/flag.png');

  runApp(MyApp(
    cascadePath: cascadePath,
    logoBytes: logoData.buffer.asUint8List(),
    flagBytes: flagData.buffer.asUint8List(),
  ));
}