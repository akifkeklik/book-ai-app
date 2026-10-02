import 'package:flutter/material.dart';
import 'design_system.dart';

class AppTheme {
  AppTheme._();

  // ── Dark Theme (Deep Onyx & Blue) ──────────────────────────────────────────
  static ThemeData darkTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      surface: DesignSystem.backgroundDark,
    ).copyWith(
      primary: seedColor,
      surfaceContainerHighest: DesignSystem.surfaceDarkHighlight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignSystem.backgroundDark,
      cardColor: DesignSystem.surfaceDark,
      textTheme: DesignSystem.textTheme(DesignSystem.textDarkPrimary),

      cardTheme: CardTheme(
        elevation: 0,
        color: DesignSystem.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          side: const BorderSide(color: Colors.white12, width: 1),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: DesignSystem.textTheme(DesignSystem.textDarkPrimary).displaySmall?.copyWith(letterSpacing: -1),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignSystem.surfaceDarkHighlight,
        border: OutlineInputBorder(borderRadius: DesignSystem.borderRadiusLarge, borderSide: BorderSide.none),
        hintStyle: DesignSystem.textTheme(DesignSystem.textDarkSecondary).bodyLarge,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: DesignSystem.borderRadiusMedium),
          padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing24, vertical: DesignSystem.spacing16),
          textStyle: DesignSystem.textTheme(Colors.white).titleMedium,
        ),
      ),
    );
  }

  // ── Light Theme (Clear Slate) ──────────────────────────────────────────────
  static ThemeData lightTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      surface: DesignSystem.backgroundLight,
    ).copyWith(
      primary: seedColor,
      surfaceContainerHighest: DesignSystem.surfaceLightHighlight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignSystem.backgroundLight,
      cardColor: DesignSystem.surfaceLight,
      textTheme: DesignSystem.textTheme(DesignSystem.textLightPrimary),

      cardTheme: CardTheme(
        elevation: 0,
        color: DesignSystem.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: DesignSystem.borderRadiusLarge,
          side: BorderSide(color: Colors.black.withOpacity(0.05), width: 1),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: DesignSystem.textTheme(DesignSystem.textLightPrimary).displaySmall?.copyWith(letterSpacing: -1),
        iconTheme: const IconThemeData(color: DesignSystem.textLightPrimary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignSystem.surfaceLightHighlight,
        border: OutlineInputBorder(borderRadius: DesignSystem.borderRadiusLarge, borderSide: BorderSide.none),
        hintStyle: DesignSystem.textTheme(DesignSystem.textLightSecondary).bodyLarge,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: DesignSystem.borderRadiusMedium),
          padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing24, vertical: DesignSystem.spacing16),
          textStyle: DesignSystem.textTheme(Colors.white).titleMedium,
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
