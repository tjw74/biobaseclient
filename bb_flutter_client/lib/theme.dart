import 'package:flutter/material.dart';

class BiobaseColors {
  static const bg = Color(0xFF080D19);
  static const surface = Color(0xFF0D1321);
  static const surfaceRaised = Color(0xFF131B2E);
  static const surfaceHover = Color(0xFF182440);
  static const border = Color(0x1494A3CC);
  static const borderSubtle = Color(0x0D94A3CC);
  static const borderHover = Color(0x2494A3CC);
  static const text = Color(0xFFE2E8F0);
  static const textSecondary = Color(0xFF94A3B8);
  static const textTertiary = Color(0xFF64748B);
  static const accent = Color(0xFF3B82F6);
  static const accentDim = Color(0x1F3B82F6);
  static const live = Color(0xFF10B981);
  static const liveDim = Color(0x1F10B981);
  static const error = Color(0xFFEF4444);
  static const errorDim = Color(0x1AEF4444);
  static const warning = Color(0xFFF59E0B);
}

ThemeData buildBiobaseTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: BiobaseColors.bg,
    fontFamily: 'Inter',
    colorScheme: const ColorScheme.dark(
      surface: BiobaseColors.surface,
      primary: BiobaseColors.accent,
      error: BiobaseColors.error,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(
          color: BiobaseColors.text, fontSize: 13, height: 1.5),
      bodyMedium: TextStyle(
          color: BiobaseColors.text, fontSize: 13, height: 1.5),
      bodySmall: TextStyle(
          color: BiobaseColors.textSecondary, fontSize: 12, height: 1.4),
      titleLarge: TextStyle(
          color: BiobaseColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4),
      labelSmall: TextStyle(
          color: BiobaseColors.accent,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0),
    ),
    dividerColor: BiobaseColors.borderSubtle,
    cardColor: BiobaseColors.surface,
  );
}
