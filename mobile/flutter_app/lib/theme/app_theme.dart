import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design_system.dart';

class AppTheme {
  AppTheme._();

  // ── Dark Theme (Supports All 6 Palettes & High Contrast) ───────────────────
  static ThemeData darkTheme(
    Color seedColor, {
    LibrisPalette palette = LibrisPalette.oceanBlue,
    bool highContrast = false,
    String fontFamily = 'editorial',
    double lineSpacing = 1.0,
  }) {
    final bgColor = highContrast ? const Color(0xFF000000) : palette.backgroundDark;
    final surfaceColor = highContrast ? const Color(0xFF121212) : palette.surfaceDark;
    final surfaceHighlight = highContrast ? const Color(0xFF242424) : palette.surfaceDarkHighlight;
    final primaryColor = highContrast ? const Color(0xFF818CF8) : (seedColor != DesignSystem.primaryDark ? seedColor : palette.primaryDark);
    final borderColor = highContrast ? const Color(0xFFFFFFFF) : Colors.white12;
    final textPrimary = highContrast ? const Color(0xFFFFFFFF) : DesignSystem.textDarkPrimary;
    final textSecondary = highContrast ? const Color(0xFFD4D4D8) : DesignSystem.textDarkSecondary;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      surface: bgColor,
    ).copyWith(
      primary: primaryColor,
      surfaceContainerHighest: surfaceHighlight,
      outline: borderColor,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgColor,
      cardColor: surfaceColor,
      textTheme: DesignSystem.textTheme(
        textPrimary,
        fontFamily: fontFamily,
        lineSpacingMultiplier: lineSpacing,
      ),

      cardTheme: CardTheme(
        elevation: 0,
        color: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          side: BorderSide(color: borderColor, width: highContrast ? 2.0 : 1.0),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: DesignSystem.textTheme(
          textPrimary,
          fontFamily: fontFamily,
        ).displaySmall?.copyWith(letterSpacing: -1),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHighlight,
        border: OutlineInputBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          borderSide: highContrast ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          borderSide: highContrast ? const BorderSide(color: Colors.white70, width: 1.5) : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        hintStyle: DesignSystem.textTheme(textSecondary, fontFamily: fontFamily).bodyLarge,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: DesignSystem.borderRadiusMedium),
          padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing24, vertical: DesignSystem.spacing16),
          textStyle: DesignSystem.textTheme(Colors.white, fontFamily: fontFamily).titleMedium,
        ),
      ),
    );
  }

  // ── Light Theme (Supports All 6 Palettes & High Contrast) ──────────────────
  static ThemeData lightTheme(
    Color seedColor, {
    LibrisPalette palette = LibrisPalette.oceanBlue,
    bool highContrast = false,
    String fontFamily = 'editorial',
    double lineSpacing = 1.0,
  }) {
    final bgColor = highContrast ? const Color(0xFFFFFFFF) : palette.backgroundLight;
    final surfaceColor = palette.surfaceLight;
    final surfaceHighlight = highContrast ? const Color(0xFFE4E4E7) : palette.surfaceLightHighlight;
    final primaryColor = highContrast ? const Color(0xFF3730A3) : (seedColor != DesignSystem.primaryLight ? seedColor : palette.primaryLight);
    final borderColor = highContrast ? const Color(0xFF000000) : Colors.black.withOpacity(0.08);
    final textPrimary = highContrast ? const Color(0xFF000000) : DesignSystem.textLightPrimary;
    final textSecondary = highContrast ? const Color(0xFF27272A) : DesignSystem.textLightSecondary;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      surface: bgColor,
    ).copyWith(
      primary: primaryColor,
      surfaceContainerHighest: surfaceHighlight,
      outline: borderColor,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgColor,
      cardColor: surfaceColor,
      textTheme: DesignSystem.textTheme(
        textPrimary,
        fontFamily: fontFamily,
        lineSpacingMultiplier: lineSpacing,
      ),

      cardTheme: CardTheme(
        elevation: 0,
        color: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          side: BorderSide(color: borderColor, width: highContrast ? 2.0 : 1.0),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: DesignSystem.textTheme(
          textPrimary,
          fontFamily: fontFamily,
        ).displaySmall?.copyWith(letterSpacing: -1),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHighlight,
        border: OutlineInputBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          borderSide: highContrast ? const BorderSide(color: Colors.black, width: 1.5) : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          borderSide: highContrast ? const BorderSide(color: Colors.black87, width: 1.5) : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        hintStyle: DesignSystem.textTheme(textSecondary, fontFamily: fontFamily).bodyLarge,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: DesignSystem.borderRadiusMedium),
          padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing24, vertical: DesignSystem.spacing16),
          textStyle: DesignSystem.textTheme(Colors.white, fontFamily: fontFamily).titleMedium,
        ),
      ),
    );
  }
}

// Extension to avoid breaking existing widget usages
extension AppThemeContext on BuildContext {
  Color get subtitleColor => Theme.of(this).colorScheme.onSurface.withOpacity(0.6);
  Color get cardColor => Theme.of(this).cardTheme.color ?? Colors.grey.shade100;
}
