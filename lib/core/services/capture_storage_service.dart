import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Where a validated capture ended up on disk, returned by
/// [CaptureStorageService.save] so the caller can show a confirmation
/// or offer to open/share the files.
class SavedCapture {
  const SavedCapture({
    required this.directory,
    required this.frontPath,
    required this.backPath,
    required this.printPagePath,
    required this.savedAt,
  });

  final String directory;
  final String frontPath;
  final String backPath;
  final String printPagePath;
  final DateTime savedAt;
}

/// Thrown by [CaptureStorageService.saveToGallery] when the user has
/// denied (or previously permanently denied) photo library / gallery
/// access. Kept as its own type - rather than surfacing whatever
/// `package:gal` throws internally - so callers (the result preview
/// screen) can show a specific, actionable message instead of a raw
/// exception string.
class GallerySaveDeniedException implements Exception {
  const GallerySaveDeniedException();

  @override
  String toString() =>
      'Accès à la galerie refusé. Autorisez l\'accès dans les réglages pour enregistrer la carte.';
}

/// Persists a validated capture (raw front/back + enhanced front/back +
/// composed print page) to the app's documents directory, under
/// `captures/<timestamp>/`, and can additionally export the
/// user-facing images (enhanced front/back + print page) to the
/// device's Photos/Gallery app.
///
/// The app-private copy (via `getApplicationDocumentsDirectory()`, same
/// `path_provider` package already used by `cascade_asset_loader.dart`
/// for the Haar cascade file) is kept as the durable, app-owned record -
/// it's what a future "browse past captures" or re-export feature would
/// read from. The gallery copy is a *separate*, additive export purely
/// so the images show up where users actually expect to find photos
/// they took: the Gallery/Photos app, not buried in app-private storage
/// they'd need a file manager to reach.
class CaptureStorageService {
  const CaptureStorageService();

  Future<SavedCapture> save({
    required Uint8List rawFront,
    required Uint8List rawBack,
    required Uint8List enhancedFront,
    required Uint8List enhancedBack,
    required Uint8List printPage,
  }) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    // Sortable-by-name timestamp folder (e.g. 20260813_143205123) so a
    // future "browse past captures" feature can just list+sort
    // directories without parsing anything.
    final folderName = _timestampFolderName(now);
    final captureDir = Directory('${documentsDir.path}/captures/$folderName');
    await captureDir.create(recursive: true);

    final frontPath = '${captureDir.path}/front_raw.png';
    final backPath = '${captureDir.path}/back_raw.png';
    final enhancedFrontPath = '${captureDir.path}/front_enhanced.png';
    final enhancedBackPath = '${captureDir.path}/back_enhanced.png';
    final printPagePath = '${captureDir.path}/print_page.png';

    await Future.wait([
      File(frontPath).writeAsBytes(rawFront, flush: true),
      File(backPath).writeAsBytes(rawBack, flush: true),
      File(enhancedFrontPath).writeAsBytes(enhancedFront, flush: true),
      File(enhancedBackPath).writeAsBytes(enhancedBack, flush: true),
      File(printPagePath).writeAsBytes(printPage, flush: true),
    ]);

    return SavedCapture(
      directory: captureDir.path,
      frontPath: enhancedFrontPath,
      backPath: enhancedBackPath,
      printPagePath: printPagePath,
      savedAt: now,
    );
  }

  /// Exports the enhanced front/back images and the composed print page
  /// to the device's Gallery/Photos app, under a dedicated album so they
  /// don't get mixed in with the user's regular camera roll.
  ///
  /// Throws [GallerySaveDeniedException] if gallery access isn't
  /// granted. Any other failure (disk full, OS-level save error, etc.)
  /// propagates as-is from `package:gal`.
  Future<void> saveToGallery({
    required Uint8List enhancedFront,
    required Uint8List enhancedBack,
    required Uint8List printPage,
  }) async {
    var hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      hasAccess = await Gal.requestAccess();
    }
    if (!hasAccess) {
      throw const GallerySaveDeniedException();
    }

    final suffix = _timestampFolderName(DateTime.now());
    const album = 'CIN Autocapture';

    // Sequential, not `Future.wait`: `Gal.putImageBytes` touches the
    // native platform channel, and several native gallery/media-store
    // writes racing each other under the same brand-new album has been a
    // source of flaky "album not found yet" failures on some Android
    // versions on first save. One at a time is a little slower but
    // reliable, and this only runs once per confirmed capture.
    await Gal.putImageBytes(enhancedFront, name: 'CIN_recto_$suffix', album: album);
    await Gal.putImageBytes(enhancedBack, name: 'CIN_verso_$suffix', album: album);
    await Gal.putImageBytes(printPage, name: 'CIN_page_impression_$suffix', album: album);
  }

  /// Lists past captures (newest first) by scanning `captures/` in the
  /// app's documents directory - the same folders [save] creates. Only
  /// returns entries that still have both enhanced images on disk (a
  /// capture folder mid-write, or one a user tampered with via a file
  /// manager, is silently skipped rather than surfaced half-broken).
  Future<List<SavedCapture>> listCaptures() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final capturesDir = Directory('${documentsDir.path}/captures');
    if (!await capturesDir.exists()) return [];

    final entries = await capturesDir.list().toList();
    final captures = <SavedCapture>[];

    for (final entry in entries) {
      if (entry is! Directory) continue;
      final folderName = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final savedAt = _parseTimestampFolderName(folderName);
      if (savedAt == null) continue;

      final frontPath = '${entry.path}/front_enhanced.png';
      final backPath = '${entry.path}/back_enhanced.png';
      final printPagePath = '${entry.path}/print_page.png';
      if (!await File(frontPath).exists() || !await File(backPath).exists()) continue;

      captures.add(SavedCapture(
        directory: entry.path,
        frontPath: frontPath,
        backPath: backPath,
        printPagePath: printPagePath,
        savedAt: savedAt,
      ));
    }

    captures.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return captures;
  }

  /// Permanently deletes one past capture's folder (and everything in
  /// it: raw + enhanced images, print page).
  Future<void> deleteCapture(String directory) async {
    final dir = Directory(directory);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  DateTime? _parseTimestampFolderName(String name) {
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(\d{3})$').firstMatch(name);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
      int.parse(match.group(7)!),
    );
  }

  String _timestampFolderName(DateTime time) {
    String pad(int value, [int width = 2]) => value.toString().padLeft(width, '0');
    return '${time.year}${pad(time.month)}${pad(time.day)}_'
        '${pad(time.hour)}${pad(time.minute)}${pad(time.second)}${pad(time.millisecond, 3)}';
  }
}