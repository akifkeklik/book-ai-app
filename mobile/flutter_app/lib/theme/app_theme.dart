import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Premium Dark Palette (Deep Slate 950/900) ──────────────────────────────
  static const Color surfaceDark = Color(0xFF020617); // Slate 950
  static const Color cardDark = Color(0xFF0F172A);    // Slate 900
  static const Color borderDark = Color(0x3394A3B8);  // Slate 400 (20% Opacity)
  
  // ── Premium Light Palette (Pristine Slate 100/50) ────────────────────────
  static const Color surfaceLight = Color(0xFFF1F5F9); // Slate 100
  static const Color cardLight = Color(0xFFF8FAFC);    // Slate 50
  static const Color borderLight = Color(0xFFE2E8F0);  // Slate 200

  // ── Text Themes ────────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme(Color onSurface) {
    return TextTheme(
      displayLarge: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: onSurface, letterSpacing: -1),
      displayMedium: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: onSurface, letterSpacing: -1),
      headlineLarge: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.5),
      headlineMedium: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: -0.5),
      titleLarge: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: onSurface),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: onSurface.withOpacity(0.9), height: 1.5, letterSpacing: 0.2),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: onSurface.withOpacity(0.8), height: 1.5),
      bodySmall: GoogleFonts.inter(fontSize: 12, color: onSurface.withOpacity(0.6)),
      labelLarge: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: onSurface, letterSpacing: 0.5),
    );
  }

  // ── Dark Theme (Deep Onyx & Blue) ──────────────────────────────────────────
  static ThemeData darkTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      surface: surfaceDark,
      background: surfaceDark,
    ).copyWith(
      primary: seedColor,
      surfaceVariant: cardDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceDark,
      cardColor: cardDark,
      textTheme: _buildTextTheme(Colors.white),
      
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        hintStyle: GoogleFonts.inter(color: Colors.white38),
      ),
    );
  }

  // ── Light Theme (Clear Slate) ──────────────────────────────────────────────
  static ThemeData lightTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      surface: surfaceLight,
      background: surfaceLight,
    ).copyWith(
      primary: seedColor,
      surfaceVariant: cardLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceLight,
      cardColor: cardLight,
      textTheme: _buildTextTheme(const Color(0xFF0F172A)),

      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.05),
        color: cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: -1),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
    );
  }
}

// Extension to avoid breaking existing widget usages
extension AppThemeContext on BuildContext {
  Color get subtitleColor => Theme.of(this).colorScheme.onSurface.withOpacity(0.6);
  Color get cardColor => Theme.of(this).cardTheme.color ?? Colors.grey.shade100;
}
