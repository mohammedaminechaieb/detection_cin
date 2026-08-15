import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/components/action_buttons.dart';
import '../../../document_detection/domain/entities/detected_document.dart';
import '../../../document_detection/domain/repositories/detection_repository.dart';

/// Horizontal margin reserved on both sides of the crop area so the
/// image - and therefore its corner drag-handles - never sits flush
/// against the physical screen edge. Without this, corners near an edge
/// compete with the OS's edge-swipe-back gesture (Android/iOS gesture
/// navigation both react to touches starting very close to the screen
/// edge), making them hard to grab. A CIN card is landscape, so once
/// fitted into a portrait screen it's usually already width-constrained
/// - meaning corners would otherwise sit almost exactly at the edge.
const double _kHandleMargin = 28.0;

/// Combined crop + rotate editor for an already-captured card image.
///
/// Rotate operates on the *whole* image (repeated 90° turns, via
/// `DetectionRepository.applyRotation` - the same primitive
/// `DetectionViewModel` uses at capture time) and is applied before crop,
/// so dragging corners always happens on the image already at the
/// orientation the person wants to keep. Crop then re-warps just that
/// oriented image against the adjusted quad.
///
/// Like the crop-only version before it, this runs on the already
/// flattened, already-captured PNG - not the original camera frame,
/// which no longer exists by the time this screen opens (disposed at the
/// end of `DetectionViewModel.onFrame` / the isolate worker's per-frame
/// handling). So "crop" here means "crop the already-flattened result
/// again", not "re-run the original perspective warp".
class EditCaptureScreen extends StatefulWidget {
  const EditCaptureScreen({
    super.key,
    required this.imageBytes,
    required this.repository,
    required this.label,
  });

  final Uint8List imageBytes;
  final DetectionRepository repository;
  final String label;

  @override
  State<EditCaptureScreen> createState() => _EditCaptureScreenState();
}

enum _EditTool { crop, rotate }

class _EditCaptureScreenState extends State<EditCaptureScreen> {
  _EditTool _tool = _EditTool.crop;

  // The bytes currently being edited - starts as the original capture,
  // replaced with a rotated version each time `_rotate90` runs, so crop
  // always operates on the current (possibly rotated) orientation.
  late Uint8List _currentBytes = widget.imageBytes;

  ui.Image? _decodedImage;
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
    final codec = await ui.instantiateImageCodec(_currentBytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _decodedImage = frame.image;
      _resetCornersToFull();
    });
  }

  void _resetCornersToFull() {
    final image = _decodedImage;
    if (image == null) return;
    _corners = [
      const Offset(0, 0),
      Offset(image.width.toDouble(), 0),
      Offset(image.width.toDouble(), image.height.toDouble()),
      Offset(0, image.height.toDouble()),
    ];
  }

  Future<void> _rotate90() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final decoded = widget.repository.decodePng(_currentBytes);
      final rotated = widget.repository.applyRotation(decoded, 90);
      final newBytes = widget.repository.encodeToPng(rotated);
      if (!identical(rotated, decoded)) {
        rotated.dispose();
      }
      decoded.dispose();

      final codec = await ui.instantiateImageCodec(newBytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;

      setState(() {
        _currentBytes = newBytes;
        _decodedImage = frame.image;
        // A fresh rotation resets any in-progress crop - keeping a crop
        // rectangle defined in the old (pre-rotation) dimensions would
        // put the corners in the wrong place on the new image.
        _resetCornersToFull();
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Rotation impossible : $e';
        _isProcessing = false;
      });
    }
  }

  /// Maps the decoded image (at its native pixel size) into the
  /// available layout space minus [_kHandleMargin] on each side,
  /// preserving aspect ratio and centering it. Every screen<->image
  /// coordinate conversion goes through this.
  Rect _displayRect(Size layoutSize) {
    final image = _decodedImage!;
    final available = Size(
      (layoutSize.width - _kHandleMargin * 2).clamp(1, double.infinity),
      layoutSize.height,
    );
    final imageAspect = image.width / image.height;
    final availableAspect = available.width / available.height;

    double w, h;
    if (imageAspect > availableAspect) {
      w = available.width;
      h = w / imageAspect;
    } else {
      h = available.height;
      w = h * imageAspect;
    }
    final left = (layoutSize.width - w) / 2;
    final top = (available.height - h) / 2;
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

  bool get _hasCropChange {
    final image = _decodedImage;
    if (image == null) return false;
    final full = [
      const Offset(0, 0),
      Offset(image.width.toDouble(), 0),
      Offset(image.width.toDouble(), image.height.toDouble()),
      Offset(0, image.height.toDouble()),
    ];
    for (var i = 0; i < 4; i++) {
      if (_corners[i] != full[i]) return true;
    }
    return false;
  }

  Future<void> _confirm() async {
    // If the person only rotated and never touched a corner, skip the
    // (lossy) re-warp entirely and just return the rotated bytes as-is -
    // warping an untouched full-frame quad is wasted work and, more
    // importantly, is a real re-encode that shouldn't happen if nothing
    // about the crop actually changed.
    if (!_hasCropChange) {
      Navigator.of(context).pop(_currentBytes);
      return;
    }

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

      final decoded = widget.repository.decodePng(_currentBytes);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Ajuster - ${widget.label}'),
        actions: [
          if (_tool == _EditTool.crop)
            IconButton(
              onPressed: _decodedImage == null ? null : () => setState(_resetCornersToFull),
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Réinitialiser le cadrage',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ToolTabs(
              selected: _tool,
              onChanged: (tool) => setState(() => _tool = tool),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _tool == _EditTool.crop
                  ? 'Faites glisser les coins pour ajuster le cadrage.'
                  : 'Faites pivoter l\'image par quart de tour.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _decodedImage == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final layoutSize = Size(constraints.maxWidth, constraints.maxHeight);
                        final displayRect = _displayRect(layoutSize);

                        if (_tool == _EditTool.rotate) {
                          return Center(
                            child: SizedBox(
                              width: displayRect.width,
                              height: displayRect.height,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                child: RawImage(image: _decodedImage, fit: BoxFit.contain),
                              ),
                            ),
                          );
                        }

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
                            if (closestDist <= kMinTouchTarget) {
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
                            painter: _CropPainter(
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
            if (_tool == _EditTool.rotate)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: _RotateButton(onPressed: _isProcessing ? null : _rotate90),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: SecondaryActionButton(
                      label: 'Annuler',
                      onPressed: _isProcessing ? null : () => Navigator.of(context).pop(null),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: PrimaryActionButton(
                      label: 'Appliquer',
                      isLoading: _isProcessing,
                      onPressed: _decodedImage == null ? null : _confirm,
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

class _ToolTabs extends StatelessWidget {
  const _ToolTabs({required this.selected, required this.onChanged});

  final _EditTool selected;
  final ValueChanged<_EditTool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: SegmentedButton<_EditTool>(
        segments: const [
          ButtonSegment(value: _EditTool.crop, label: Text('Recadrer'), icon: Icon(Icons.crop)),
          ButtonSegment(
            value: _EditTool.rotate,
            label: Text('Pivoter'),
            icon: Icon(Icons.rotate_90_degrees_cw),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _RotateButton extends StatelessWidget {
  const _RotateButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMinTouchTarget,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.rotate_90_degrees_cw),
        label: const Text('Pivoter de 90°'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
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

    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
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
      canvas.drawCircle(corners[i], isDragging ? 16 : 12, Paint()..color = Colors.white);
      canvas.drawCircle(
        corners[i],
        isDragging ? 16 : 12,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.draggingIndex != draggingIndex ||
        oldDelegate.displayRect != displayRect ||
        !identical(oldDelegate.image, image);
  }
}