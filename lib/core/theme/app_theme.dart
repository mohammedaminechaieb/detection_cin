import 'package:flutter/material.dart';

/// Shared visual language for the capture flow (camera, status banner,
/// result preview, recrop, enhancement picker) - centralized so the
/// Step 4 UI/UX pass reads as one coherent flow rather than four
/// separately-styled screens.
class AppColors {
  const AppColors._();

  static const background = Color(0xFF0B0B0D);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceRaised = Color(0xFF2C2C2E);

  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFF9F0A);
  static const danger = Color(0xFFFF453A);

  static const textPrimary = Colors.white;
  static const textSecondary = Colors.white70;
  static const textTertiary = Colors.white38;

  static const accent = Color(0xFF0A84FF);
}

class AppSpacing {
  const AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AppRadius {
  const AppRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
}

class AppDurations {
  const AppDurations._();

  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const screenTransition = Duration(milliseconds: 300);
}

/// Minimum touch-target side length, per standard accessibility
/// guidance (WCAG 2.5.5 / Apple HIG both land around 44pt).
const double kMinTouchTarget = 44.0;