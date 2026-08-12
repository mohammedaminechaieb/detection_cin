import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../document_detection/domain/entities/detected_document.dart';
import '../../../document_detection/domain/repositories/detection_repository.dart';

/// Lets the user manually adjust the crop on an already-captured card
/// image by dragging its four corners, then re-warps the image against
/// the adjusted quad.
///
/// This operates on the card image *as already captured* (perspective-
/// corrected once already, from the live detection pass), not on the
/// original camera frame - that frame is long gone by the time the user
/// reaches the result preview (disposed at the end of
/// `DetectionViewModel.onFrame`). So this is a second warp on top of the
/// first: the four draggable corners start at the image's own corners
/// (full quad = no change), and dragging them inward crops + re-flattens
/// that sub-region. If the auto-detected quad was close but not exact,
/// this corrects the remaining error; it can't recover detail that was
/// already cropped out by the first (auto) warp.
class RecropScreen extends StatefulWidget {
  const RecropScreen({
    super.key,
    required this.imageBytes,
    required this.repository,
    required this.label,
  });

  final Uint8List imageBytes;
  final DetectionRepository repository;
  final String label;

  @override
  State<RecropScreen> createState() => _RecropScreenState();
}

class _RecropScreenState extends State<RecropScreen> {
  ui.Image? _decodedImage;
  // Corner positions in *source image pixel* coordinates (not screen
  // coordinates) - converted to/from screen space at paint/hit-test time
  // via the current `_displayRect`, so they stay correct across resizes.
  late List<Offset> _corners;
  int? _draggingIndex;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _decodedImage = frame.image;
      _corners = [
        const Offset(0, 0),
        Offset(frame.image.width.toDouble(), 0),
        Offset(frame.image.width.toDouble(), frame.image.height.toDouble()),
        Offset(0, frame.image.height.toDouble()),
      ];
    });
  }

  /// Maps the decoded image (at its native pixel size) into the
  /// available layout space, preserving aspect ratio and centering it -
  /// matching `BoxFit.contain`, since that's what the image is displayed
  /// with. Every screen<->image coordinate conversion goes through this.
  Rect _displayRect(Size layoutSize) {
    final image = _decodedImage!;
    final imageAspect = image.width / image.height;
    final layoutAspect = layoutSize.width / layoutSize.height;

    double w, h;
    if (imageAspect > layoutAspect) {
      w = layoutSize.width;
      h = w / imageAspect;
    } else {
      h = layoutSize.height;
      w = h * imageAspect;
    }
    final left = (layoutSize.width - w) / 2;
    final top = (layoutSize.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  Offset _imageToScreen(Offset imagePoint, Rect displayRect) {
    final image = _decodedImage!;
    final sx = displayRect.width / image.width;
    final sy = displayRect.height / image.height;
    return Offset(
      displayRect.left + imagePoint.dx * sx,
      displayRect.top + imagePoint.dy * sy,
    );
  }

  Offset _screenToImage(Offset screenPoint, Rect displayRect) {
    final image = _decodedImage!;
    final sx = image.width / displayRect.width;
    final sy = image.height / displayRect.height;
    return Offset(
      (screenPoint.dx - displayRect.left) * sx,
      (screenPoint.dy - displayRect.top) * sy,
    );
  }

  Future<void> _confirm() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final quad = CardQuad(
        topLeft: CardPoint(_corners[0].dx, _corners[0].dy),
        topRight: CardPoint(_corners[1].dx, _corners[1].dy),
        bottomRight: CardPoint(_corners[2].dx, _corners[2].dy),
        bottomLeft: CardPoint(_corners[3].dx, _corners[3].dy),
      );

      final decoded = widget.repository.decodePng(widget.imageBytes);
      final rewarped = widget.repository.warpDocument(decoded, quad);
      final pngBytes = widget.repository.encodeToPng(rewarped);
      decoded.dispose();
      rewarped.dispose();

      if (!mounted) return;
      Navigator.of(context).pop(pngBytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Recadrage impossible : $e';
        _isProcessing = false;
      });
    }
  }

  void _resetCorners() {
    final image = _decodedImage;
    if (image == null) return;
    setState(() {
      _corners = [
        const Offset(0, 0),
        Offset(image.width.toDouble(), 0),
        Offset(image.width.toDouble(), image.height.toDouble()),
        Offset(0, image.height.toDouble()),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Recadrer - ${widget.label}'),
        actions: [
          IconButton(
            onPressed: _decodedImage == null ? null : _resetCorners,
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Réinitialiser le cadrage',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Faites glisser les coins pour ajuster le cadrage.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: _decodedImage == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final layoutSize = Size(constraints.maxWidth, constraints.maxHeight);
                        final displayRect = _displayRect(layoutSize);

                        return GestureDetector(
                          onPanStart: (details) {
                            final local = details.localPosition;
                            var closestIndex = 0;
                            var closestDist = double.infinity;
                            for (var i = 0; i < _corners.length; i++) {
                              final screenPos = _imageToScreen(_corners[i], displayRect);
                              final dist = (screenPos - local).distance;
                              if (dist < closestDist) {
                                closestDist = dist;
                                closestIndex = i;
                              }
                            }
                            // 44px minimum touch target, per standard
                            // accessibility guidance - only start a drag
                            // if the touch actually landed near a handle.
                            if (closestDist <= 44) {
                              setState(() => _draggingIndex = closestIndex);
                            }
                          },
                          onPanUpdate: (details) {
                            final index = _draggingIndex;
                            if (index == null) return;
                            final imagePoint = _screenToImage(details.localPosition, displayRect);
                            final image = _decodedImage!;
                            setState(() {
                              _corners[index] = Offset(
                                imagePoint.dx.clamp(0, image.width.toDouble()),
                                imagePoint.dy.clamp(0, image.height.toDouble()),
                              );
                            });
                          },
                          onPanEnd: (_) => setState(() => _draggingIndex = null),
                          child: CustomPaint(
                            size: layoutSize,
                            painter: _RecropPainter(
                              image: _decodedImage!,
                              displayRect: displayRect,
                              corners: _corners.map((c) => _imageToScreen(c, displayRect)).toList(),
                              draggingIndex: _draggingIndex,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : () => Navigator.of(context).pop(null),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isProcessing || _decodedImage == null ? null : _confirm,
                      child: _isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Appliquer'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecropPainter extends CustomPainter {
  _RecropPainter({
    required this.image,
    required this.displayRect,
    required this.corners,
    required this.draggingIndex,
  });

  final ui.Image image;
  final Rect displayRect;
  final List<Offset> corners;
  final int? draggingIndex;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      displayRect,
      Paint(),
    );

    // Using `withOpacity` (not the newer `withValues`) since this repo's
    // Flutter SDK constraint isn't in what I was given (no pubspec.yaml) -
    // `withOpacity` works on every Flutter version currently in
    // widespread use, so it's the safer choice here.
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.45);
    final quadPath = Path()..addPolygon(corners, true);
    final overlayPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      quadPath,
    );
    canvas.drawPath(overlayPath, overlayPaint);

    final linePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(quadPath, linePaint);

    for (var i = 0; i < corners.length; i++) {
      final isDragging = draggingIndex == i;
      canvas.drawCircle(
        corners[i],
        isDragging ? 16 : 12,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        corners[i],
        isDragging ? 16 : 12,
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecropPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.draggingIndex != draggingIndex ||
        oldDelegate.displayRect != displayRect;
  }
}