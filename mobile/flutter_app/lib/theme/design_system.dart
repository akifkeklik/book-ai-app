import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A premium, consistent Design System for Libris.
class DesignSystem {
  DesignSystem._();

  // ── Colors ─────────────────────────────────────────────────────────────────

  static const Color primaryDark = Color(0xFF6366F1); // Indigo 500
  static const Color primaryLight = Color(0xFF4F46E5); // Indigo 600

  static const Color backgroundDark = Color(0xFF0F172A); // Slate 900
  static const Color surfaceDark = Color(0xFF1E293B);    // Slate 800
  static const Color surfaceDarkHighlight = Color(0xFF334155); // Slate 700

  static const Color backgroundLight = Color(0xFFF8FAFC); // Slate 50
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceLightHighlight = Color(0xFFF1F5F9); // Slate 100

  static const Color textDarkPrimary = Color(0xFFF8FAFC);
  static const Color textDarkSecondary = Color(0xFF94A3B8);

  static const Color textLightPrimary = Color(0xFF0F172A);
  static const Color textLightSecondary = Color(0xFF64748B);

  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
  static const Color favorite = Color(0xFFF43F5E); // Rose 500
  static const Color rating = Color(0xFFFFD166);

  // ── Spacing ────────────────────────────────────────────────────────────────

  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;

  // ── Border Radius ──────────────────────────────────────────────────────────

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge = 24.0;
  static const double radiusPill = 999.0;

  static BorderRadius get borderRadiusSmall => BorderRadius.circular(radiusSmall);
  static BorderRadius get borderRadiusMedium => BorderRadius.circular(radiusMedium);
  static BorderRadius get borderRadiusLarge => BorderRadius.circular(radiusLarge);
  static BorderRadius get borderRadiusPill => BorderRadius.circular(radiusPill);

  // ── Shadows ────────────────────────────────────────────────────────────────

  static List<BoxShadow> shadowSm(bool isDark) => [
    BoxShadow(
      color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
      blurRadius: 4,
      offset: const Offset(0, 2),
    )
  ];

  static List<BoxShadow> shadowMd(bool isDark) => [
    BoxShadow(
      color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.08),
      blurRadius: 8,
      offset: const Offset(0, 4),
    )
  ];

  static List<BoxShadow> shadowLg(bool isDark) => [
    BoxShadow(
      color: isDark ? Colors.black.withOpacity(0.5) : Colors.black.withOpacity(0.12),
      blurRadius: 16,
      offset: const Offset(0, 8),
    )
  ];

  static List<BoxShadow> shadowGlow(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    )
  ];

  // ── Typography ─────────────────────────────────────────────────────────────

  static TextTheme textTheme(Color color) {
    return TextTheme(
      displayLarge: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: color, letterSpacing: -1),
      displayMedium: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: color, letterSpacing: -0.5),
      displaySmall: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: color),
      headlineLarge: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: color),
      headlineMedium: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w600, color: color),
      headlineSmall: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: color),
      titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: color),
      titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: color),
      titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: color, height: 1.5),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: color, height: 1.5),
      bodySmall: GoogleFonts.inter(fontSize: 12, color: color),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      labelSmall: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.5),
    );
  }
}
