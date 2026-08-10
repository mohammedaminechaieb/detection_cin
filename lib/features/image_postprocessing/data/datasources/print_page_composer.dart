import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compose les images recto et verso d'une carte sur une seule page
/// blanche prête à l'impression (A4 portrait @ 300dpi par défaut),
/// empilées verticalement avec marges - même mise en page qu'un
/// scanner classique.
///
/// ASSOMPTION NON VÉRIFIÉE : API `package:image` v4.x (`img.Image(width:,
/// height:)`, `img.fill(image, color:)`, `img.compositeImage(dst, src,
/// dstX:, dstY:)`, `img.copyResize(image, width:, height:)`). À ajuster
/// si `flutter analyze` le signale.
class PrintPageComposer {
  const PrintPageComposer({
    this.pageWidth = 2480, // A4 portrait @ 300dpi
    this.pageHeight = 3508,
    this.margin = 120,
    this.gap = 80,
  });

  final int pageWidth;
  final int pageHeight;
  final int margin;
  final int gap;

  Uint8List compose(Uint8List frontPng, Uint8List backPng) {
    final front = img.decodePng(frontPng);
    final back = img.decodePng(backPng);
    if (front == null || back == null) {
      throw StateError('Impossible de décoder une des deux images pour la page à imprimer.');
    }

    final page = img.Image(width: pageWidth, height: pageHeight);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));

    final slotWidth = pageWidth - margin * 2;
    final slotHeight = (pageHeight - margin * 2 - gap) ~/ 2;

    _placeCentered(page, front, x: margin, y: margin, maxWidth: slotWidth, maxHeight: slotHeight);
    _placeCentered(
      page,
      back,
      x: margin,
      y: margin + slotHeight + gap,
      maxWidth: slotWidth,
      maxHeight: slotHeight,
    );

    return Uint8List.fromList(img.encodePng(page));
  }

  void _placeCentered(
    img.Image page,
    img.Image image, {
    required int x,
    required int y,
    required int maxWidth,
    required int maxHeight,
  }) {
    final scale = [maxWidth / image.width, maxHeight / image.height].reduce((a, b) => a < b ? a : b);
    final targetWidth = (image.width * scale).round();
    final targetHeight = (image.height * scale).round();
    final resized = img.copyResize(image, width: targetWidth, height: targetHeight);

    final offsetX = x + (maxWidth - targetWidth) ~/ 2;
    final offsetY = y + (maxHeight - targetHeight) ~/ 2;

    img.compositeImage(page, resized, dstX: offsetX, dstY: offsetY);
  }
}