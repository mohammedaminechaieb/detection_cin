import 'package:flutter/material.dart';
import '../../../document_detection/domain/entities/detected_document.dart';

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: [
            Positioned(
              left: w * 0.03,
              top: h * 0.05,
              width: w * 0.24,
              height: h * 0.30,
              child: _GuideImage(assetPath: 'assets/guides/flag_outline.png', detected: isFlagDetected),
            ),
            Positioned(
              right: w * 0.05,
              top: h * 0.05,
              width: w * 0.22,
              height: h * 0.30,
              child: _GuideImage(assetPath: 'assets/guides/emblem_outline.png', detected: isLogoDetected),
            ),
            Positioned(
              left: w * 0.03,
              bottom: h * 0.06,
              width: w * 0.28,
              height: h * 0.45,
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: [
            
            Positioned(
              left: w * 0.68,
              top: h * 0.28,
              width: w * 0.30,
              height: h * 0.48,
              child: _GuideIcon(icon: Icons.fingerprint, detected: isFingerprintDetected),
            ),

            
            
            
            Positioned(
              left: w * 0.17,
              top: h * 0.775,
              width: w * 0.67,
              height: h * 0.035,
              child: _GuideBar(detected: isSeparationLineDetected, direction: Axis.horizontal),
            ),

            
            
            Positioned(
              left: w * 0.22,
              top: h * 0.82,
              width: w * 0.47,
              height: h * 0.15,
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