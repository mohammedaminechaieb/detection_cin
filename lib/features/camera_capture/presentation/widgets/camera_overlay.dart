import 'package:flutter/material.dart';
import '../../../document_detection/domain/entities/detected_document.dart';

/// A guide-silhouette placement, expressed as fractions of the card
/// overlay's rendered width/height rather than raw pixels, mirroring how
/// [Positioned] itself is used below. Exactly one of [left]/[right] and
/// exactly one of [top]/[bottom] must be set, matching whichever edge
/// each silhouette is anchored to.
class _GuideRect {
  const _GuideRect({
    this.left,
    this.right,
    this.top,
    this.bottom,
    required this.width,
    required this.height,
  }) : assert(
          (left == null) != (right == null),
          'Set exactly one of left/right.',
        ),
        assert(
          (top == null) != (bottom == null),
          'Set exactly one of top/bottom.',
        );

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double width;
  final double height;

  Widget position(double w, double h, {required Widget child}) => Positioned(
        left: left == null ? null : w * left!,
        right: right == null ? null : w * right!,
        top: top == null ? null : h * top!,
        bottom: bottom == null ? null : h * bottom!,
        width: w * width,
        height: h * height,
        child: child,
      );
}

class CameraOverlay extends StatelessWidget {
  final CardSide side;
  final bool isBorderDetected;

  final bool isFaceDetected;
  final bool isLogoDetected;
  final bool isFlagDetected;

  final bool isBarcodeDetected;
  final bool isFingerprintDetected;
  final bool isSeparationLineDetected;

  const CameraOverlay({
    super.key,
    required this.side,
    required this.isBorderDetected,
    this.isFaceDetected = false,
    this.isLogoDetected = false,
    this.isFlagDetected = false,
    this.isBarcodeDetected = false,
    this.isFingerprintDetected = false,
    this.isSeparationLineDetected = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isBorderDetected ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1.58,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: side == CardSide.front
                ? _FrontGuideSilhouettes(
                    isFaceDetected: isFaceDetected,
                    isLogoDetected: isLogoDetected,
                    isFlagDetected: isFlagDetected,
                  )
                : _BackGuideSilhouettes(
                    isBarcodeDetected: isBarcodeDetected,
                    isFingerprintDetected: isFingerprintDetected,
                    isSeparationLineDetected: isSeparationLineDetected,
                  ),
          ),
        ),
      ),
    );
  }
}

class _FrontGuideSilhouettes extends StatelessWidget {
  final bool isFaceDetected;
  final bool isLogoDetected;
  final bool isFlagDetected;

  const _FrontGuideSilhouettes({
    required this.isFaceDetected,
    required this.isLogoDetected,
    required this.isFlagDetected,
  });

  // Hand-tuned against the Tunisian CIN's physical front layout (flag
  // top-left, national emblem top-right, ID photo bottom-left). Named
  // here - rather than left as bare literals inline - so there's a
  // single place to look if that physical layout ever needs adjusting.
  static const _flagRect = _GuideRect(left: 0.03, top: 0.05, width: 0.24, height: 0.30);
  static const _emblemRect = _GuideRect(right: 0.05, top: 0.05, width: 0.22, height: 0.30);
  static const _faceRect = _GuideRect(left: 0.03, bottom: 0.06, width: 0.28, height: 0.45);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: [
            _flagRect.position(
              w,
              h,
              child: _GuideImage(assetPath: 'assets/guides/flag_outline.png', detected: isFlagDetected),
            ),
            _emblemRect.position(
              w,
              h,
              child: _GuideImage(assetPath: 'assets/guides/emblem_outline.png', detected: isLogoDetected),
            ),
            _faceRect.position(
              w,
              h,
              child: _GuideIcon(icon: Icons.person_outline, detected: isFaceDetected),
            ),
          ],
        );
      },
    );
  }
}

class _BackGuideSilhouettes extends StatelessWidget {
  final bool isBarcodeDetected;
  final bool isFingerprintDetected;
  final bool isSeparationLineDetected;

  const _BackGuideSilhouettes({
    required this.isBarcodeDetected,
    required this.isFingerprintDetected,
    required this.isSeparationLineDetected,
  });

  // Hand-tuned against the Tunisian CIN's physical back layout
  // (fingerprint top-right, separation line and barcode stacked near the
  // bottom). Named here for the same reason as `_FrontGuideSilhouettes`'s
  // rects above.
  static const _fingerprintRect = _GuideRect(left: 0.68, top: 0.28, width: 0.30, height: 0.48);
  static const _separationLineRect = _GuideRect(left: 0.17, top: 0.775, width: 0.67, height: 0.035);
  static const _barcodeRect = _GuideRect(left: 0.22, top: 0.82, width: 0.47, height: 0.15);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: [
            _fingerprintRect.position(
              w,
              h,
              child: _GuideIcon(icon: Icons.fingerprint, detected: isFingerprintDetected),
            ),
            _separationLineRect.position(
              w,
              h,
              child: _GuideBar(detected: isSeparationLineDetected, direction: Axis.horizontal),
            ),
            _barcodeRect.position(
              w,
              h,
              child: _GuideImage(
                assetPath: 'assets/guides/barcode_outline.png',
                detected: isBarcodeDetected,
                fallbackIcon: Icons.qr_code_2,
                fit: BoxFit.fitWidth,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GuideImage extends StatelessWidget {
  final String assetPath;
  final bool detected;
  final IconData fallbackIcon;
  final BoxFit fit;

  const _GuideImage({
    required this.assetPath,
    required this.detected,
    this.fallbackIcon = Icons.image_not_supported_outlined,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final color = detected ? Colors.green : Colors.red;

    return SizedBox.expand(
      child: Image.asset(
        assetPath,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        fit: fit,

        errorBuilder: (context, error, stackTrace) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest.shortestSide.clamp(16.0, 200.0) * 0.75;
              return Center(child: Icon(fallbackIcon, color: color, size: size));
            },
          );
        },
      ),
    );
  }
}

class _GuideIcon extends StatelessWidget {
  final IconData icon;
  final bool detected;

  const _GuideIcon({required this.icon, required this.detected});

  @override
  Widget build(BuildContext context) {
    final color = detected ? Colors.green : Colors.red;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide.clamp(16.0, 200.0) * 0.75;
        return Center(child: Icon(icon, color: color, size: size));
      },
    );
  }
}

class _GuideBar extends StatelessWidget {
  final bool detected;
  final Axis direction;

  const _GuideBar({required this.detected, this.direction = Axis.horizontal});

  @override
  Widget build(BuildContext context) {
    final color = detected ? Colors.green : Colors.red;
    return Center(
      child: Container(
        width: direction == Axis.horizontal ? double.infinity : 6,
        height: direction == Axis.vertical ? double.infinity : 6,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}