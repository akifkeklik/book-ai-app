import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Available palettes for Libris
enum LibrisPalette {
  oceanBlue,
  forestGreen,
  lavender,
  terracotta,
  amber,
  turquoise;

  static List<LibrisPalette> get canonicalSix => values;

  String get id {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return 'ocean_blue';
      case LibrisPalette.forestGreen:
        return 'forest_green';
      case LibrisPalette.lavender:
        return 'lavender';
      case LibrisPalette.terracotta:
        return 'terracotta';
      case LibrisPalette.amber:
        return 'amber';
      case LibrisPalette.turquoise:
        return 'turquoise';
    }
  }

  String get translationKey {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return 'palette_ocean_blue';
      case LibrisPalette.forestGreen:
        return 'palette_forest_green';
      case LibrisPalette.lavender:
        return 'palette_lavender';
      case LibrisPalette.terracotta:
        return 'palette_terracotta';
      case LibrisPalette.amber:
        return 'palette_amber';
      case LibrisPalette.turquoise:
        return 'palette_turquoise';
    }
  }

  Color get primaryDark {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return const Color(0xFF38BDF8); // Powder / Ocean Sky
      case LibrisPalette.forestGreen:
        return const Color(0xFF34D399); // Sage / Forest Emerald
      case LibrisPalette.lavender:
        return const Color(0xFFA78BFA); // Soft Lavender
      case LibrisPalette.terracotta:
        return const Color(0xFFFB923C); // Warm Terracotta / Apricot
      case LibrisPalette.amber:
        return const Color(0xFFFBBF24); // Warm Golden Amber
      case LibrisPalette.turquoise:
        return const Color(0xFF2DD4BF); // Vibrant Turquoise
    }
  }

  Color get primaryLight {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return const Color(0xFF0284C7);
      case LibrisPalette.forestGreen:
        return const Color(0xFF059669);
      case LibrisPalette.lavender:
        return const Color(0xFF7C3AED);
      case LibrisPalette.terracotta:
        return const Color(0xFFC2410C);
      case LibrisPalette.amber:
        return const Color(0xFFD97706);
      case LibrisPalette.turquoise:
        return const Color(0xFF0D9488);
    }
  }

  Color get backgroundDark {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return const Color(0xFF090E17);
      case LibrisPalette.forestGreen:
        return const Color(0xFF0E1C14);
      case LibrisPalette.lavender:
        return const Color(0xFF161329);
      case LibrisPalette.terracotta:
        return const Color(0xFF221611);
      case LibrisPalette.amber:
        return const Color(0xFF1C1608);
      case LibrisPalette.turquoise:
        return const Color(0xFF091B1A);
    }
  }

  Color get surfaceDark {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return const Color(0xFF0F172A);
      case LibrisPalette.forestGreen:
        return const Color(0xFF162A1F);
      case LibrisPalette.lavender:
        return const Color(0xFF231E3D);
      case LibrisPalette.terracotta:
        return const Color(0xFF33211A);
      case LibrisPalette.amber:
        return const Color(0xFF2A210D);
      case LibrisPalette.turquoise:
        return const Color(0xFF112B2A);
    }
  }

  Color get surfaceDarkHighlight {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return const Color(0xFF162238);
      case LibrisPalette.forestGreen:
        return const Color(0xFF213D2D);
      case LibrisPalette.lavender:
        return const Color(0xFF342E56);
      case LibrisPalette.terracotta:
        return const Color(0xFF483025);
      case LibrisPalette.amber:
        return const Color(0xFF3E3114);
      case LibrisPalette.turquoise:
        return const Color(0xFF183F3E);
    }
  }

  Color get backgroundLight {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return const Color(0xFFF0F7FF);
      case LibrisPalette.forestGreen:
        return const Color(0xFFF0F8F4);
      case LibrisPalette.lavender:
        return const Color(0xFFF7F5FC);
      case LibrisPalette.terracotta:
        return const Color(0xFFFDF6F0);
      case LibrisPalette.amber:
        return const Color(0xFFFFFDF5);
      case LibrisPalette.turquoise:
        return const Color(0xFFF0FDFA);
    }
  }

  Color get surfaceLight {
    return const Color(0xFFFFFFFF);
  }

  Color get surfaceLightHighlight {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return const Color(0xFFE0F2FE);
      case LibrisPalette.forestGreen:
        return const Color(0xFFD1FAE5);
      case LibrisPalette.lavender:
        return const Color(0xFFEDE9FE);
      case LibrisPalette.terracotta:
        return const Color(0xFFFFEDD5);
      case LibrisPalette.amber:
        return const Color(0xFFFEF3C7);
      case LibrisPalette.turquoise:
        return const Color(0xFFCCFBF1);
    }
  }

  Color get accent {
    switch (this) {
      case LibrisPalette.oceanBlue:
        return const Color(0xFF0EA5E9);
      case LibrisPalette.forestGreen:
        return const Color(0xFF059669);
      case LibrisPalette.lavender:
        return const Color(0xFFC084FC);
      case LibrisPalette.terracotta:
        return const Color(0xFFEA580C);
      case LibrisPalette.amber:
        return const Color(0xFFF59E0B);
      case LibrisPalette.turquoise:
        return const Color(0xFF0D9488);
    }
  }

  static LibrisPalette fromId(String? id) {
    switch (id) {
      case 'forest_green':
      case 'forestGreen':
      case 'sage':
        return LibrisPalette.forestGreen;
      case 'lavender':
        return LibrisPalette.lavender;
      case 'terracotta':
      case 'peach':
        return LibrisPalette.terracotta;
      case 'amber':
        return LibrisPalette.amber;
      case 'turquoise':
        return LibrisPalette.turquoise;
      case 'ocean_blue':
      case 'oceanBlue':
      case 'powder_blue':
      case 'powderBlue':
      case 'editorial':
      default:
        return LibrisPalette.oceanBlue;
    }
  }
}

/// A premium, consistent Design System for Libris across Mobile and Web.
class DesignSystem {
  DesignSystem._();

  // ── Core Brand Defaults (Editorial Palette) ───────────────────────────────
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

  static const Color canvasDeep = Color(0xFF0B0F19);
  static const Color accent = Color(0xFF8B5CF6); // Violet 500

  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
  static const Color favorite = Color(0xFFF43F5E); // Rose 500
  static const Color rating = Color(0xFFFFD166);

  // ── Complete Semantic Roles (Cross-Client Parity) ──────────────────────────
  static const Color focus = Color(0xFF6366F1);
  static const Color link = Color(0xFF60A5FA);
  static const Color disabled = Color(0xFF64748B);
  static const Color overlay = Color(0x99000000);
  static const Color accentForeground = Color(0xFFFFFFFF);

  // ── Reading Status & Signal Tokens ─────────────────────────────────────────
  static const Color statusFavorite = Color(0xFFF43F5E); // Rose 500
  static const Color statusReading = Color(0xFFF59E0B);  // Amber 500
  static const Color statusWantToRead = Color(0xFF38BDF8); // Sky 400
  static const Color statusFinished = Color(0xFF10B981); // Emerald 500
  static const Color statusLike = Color(0xFF6366F1);     // Indigo 500
  static const Color statusDislike = Color(0xFF64748B);  // Slate 500

  static const Color borderDark = Color(0x1FFFFFFF);
  static const Color borderLight = Color(0x1A000000);
  static const Color borderHighContrast = Color(0xFFFFFFFF);

  // ── Spacing Scale ──────────────────────────────────────────────────────────
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

  // ── SaaS Dark Navy & Electric Blue Tokens ─────────────────────────────────
  static const Color saasCanvasDeep = Color(0xFF060911);
  static const Color saasNavy950 = Color(0xFF090E17);
  static const Color saasNavy900 = Color(0xFF0F172A);
  static const Color saasNavy800 = Color(0xFF162238);
  static const Color saasNavy700 = Color(0xFF1E2E4A);
  static const Color saasCharcoal = Color(0xFF121824);

  static const Color electricBlue = Color(0xFF38BDF8);
  static const Color electricBlueHover = Color(0xFF0EA5E9);
  static const Color electricBlueMuted = Color(0x1F38BDF8); // 0.12 opacity
  static const Color electricBlueBorder = Color(0x4738BDF8); // 0.28 opacity

  static List<BoxShadow> saasCardShadow(bool isDark) => [
    BoxShadow(
      color: isDark ? Colors.black.withOpacity(0.55) : Colors.black.withOpacity(0.06),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> saasCardHoverShadow(bool isDark) => [
    BoxShadow(
      color: isDark ? Colors.black.withOpacity(0.65) : Colors.black.withOpacity(0.1),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: electricBlue.withOpacity(0.25),
      blurRadius: 18,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> saasElectricGlow() => [
    BoxShadow(
      color: electricBlue.withOpacity(0.35),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  static bool disableGoogleFontsInTests = false;

  // ── Typography Scale & Hierarchies ─────────────────────────────────────────
  static TextTheme textTheme(
    Color color, {
    String fontFamily = 'editorial',
    double lineSpacingMultiplier = 1.0,
  }) {
    final double bodyHeight = 1.5 * lineSpacingMultiplier;

    // Display Font
    TextStyle displayStyle(double size, FontWeight weight, {double? letterSpacing}) {
      if (disableGoogleFontsInTests) {
        return TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        );
      }
      if (fontFamily == 'serif') {
        return GoogleFonts.playfairDisplay(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        );
      } else if (fontFamily == 'mono') {
        return GoogleFonts.jetBrainsMono(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        );
      }
      return GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );
    }

    // Body Font
    TextStyle bodyStyle(double size, {FontWeight? weight, double? height}) {
      if (disableGoogleFontsInTests) {
        return TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height ?? bodyHeight,
        );
      }
      if (fontFamily == 'serif') {
        return GoogleFonts.playfairDisplay(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height ?? bodyHeight,
        );
      } else if (fontFamily == 'mono') {
        return GoogleFonts.jetBrainsMono(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height ?? bodyHeight,
        );
      }
      return GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height ?? bodyHeight,
      );
    }

    return TextTheme(
      displayLarge: displayStyle(32, FontWeight.bold, letterSpacing: -1),
      displayMedium: displayStyle(28, FontWeight.bold, letterSpacing: -0.5),
      displaySmall: displayStyle(24, FontWeight.bold),
      headlineLarge: displayStyle(22, FontWeight.w700),
      headlineMedium: displayStyle(20, FontWeight.w600),
      headlineSmall: displayStyle(18, FontWeight.w600),
      titleLarge: bodyStyle(18, weight: FontWeight.w600),
      titleMedium: bodyStyle(16, weight: FontWeight.w600),
      titleSmall: bodyStyle(14, weight: FontWeight.w600),
      bodyLarge: bodyStyle(16),
      bodyMedium: bodyStyle(14),
      bodySmall: bodyStyle(12),
      labelLarge: bodyStyle(14, weight: FontWeight.bold),
      labelMedium: bodyStyle(12, weight: FontWeight.w600),
      labelSmall: bodyStyle(10, weight: FontWeight.w600),
    );
  }
}
