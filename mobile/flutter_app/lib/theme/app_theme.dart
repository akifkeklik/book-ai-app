import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Palette ────────────────────────────────────────────────────────────────
  static const Color _primaryTeal = Color(0xFF00B4D8);
  static const Color _accentGold = Color(0xFFFFD166);

  // Dark
  static const Color _darkBg = Color(0xFF0D1B2A);
  static const Color _darkSurface = Color(0xFF1B2A3B);
  static const Color _darkCard = Color(0xFF243447);
  static const Color _darkSubtitle = Color(0xFF8899AA);

  // Light
  static const Color _lightBg = Color(0xFFF0F4F8);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightCard = Color(0xFFE8EFF6);
  static const Color _lightSubtitle = Color(0xFF637080);

  // ── Text themes ────────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme(Color onSurface) {
    final base = GoogleFonts.poppinsTextTheme();
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(color: onSurface, fontWeight: FontWeight.w700),
      displayMedium: base.displayMedium?.copyWith(color: onSurface, fontWeight: FontWeight.w700),
      headlineLarge: GoogleFonts.poppins(
        fontSize: 24, fontWeight: FontWeight.w700, color: onSurface),
      headlineMedium: GoogleFonts.poppins(
        fontSize: 20, fontWeight: FontWeight.w600, color: onSurface),
      headlineSmall: GoogleFonts.poppins(
        fontSize: 18, fontWeight: FontWeight.w600, color: onSurface),
      titleLarge: GoogleFonts.poppins(
        fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
      titleMedium: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w500, color: onSurface),
      titleSmall: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w500, color: onSurface),
      bodyLarge: GoogleFonts.inter(fontSize: 15, color: onSurface),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: onSurface),
      bodySmall: GoogleFonts.inter(fontSize: 12, color: onSurface.withOpacity(0.7)),
      labelLarge: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
    );
  }

  // ── Dark theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _darkBg,
        colorScheme: const ColorScheme.dark(
          primary: _primaryTeal,
          secondary: _accentGold,
          surface: _darkSurface,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
        ),
        textTheme: _buildTextTheme(Colors.white),
        appBarTheme: AppBarTheme(
          backgroundColor: _darkBg,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        cardTheme: CardTheme(
          color: _darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _darkSurface,
          hintStyle: GoogleFonts.inter(color: _darkSubtitle),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryTeal, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryTeal,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _darkCard,
          selectedColor: _primaryTeal.withOpacity(0.2),
          labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dividerTheme: const DividerThemeData(color: _darkCard, thickness: 1),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _darkCard,
          contentTextStyle: GoogleFonts.inter(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _darkSurface,
          selectedItemColor: _primaryTeal,
          unselectedItemColor: _darkSubtitle,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        extensions: const [_AppColors(subtitle: _darkSubtitle, card: _darkCard)],
      );

  // ── Light theme ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: _lightBg,
        colorScheme: const ColorScheme.light(
          primary: _primaryTeal,
          secondary: _accentGold,
          surface: _lightSurface,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Color(0xFF0D1B2A),
        ),
        textTheme: _buildTextTheme(const Color(0xFF0D1B2A)),
        appBarTheme: AppBarTheme(
          backgroundColor: _lightSurface,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF0D1B2A)),
        ),
        cardTheme: CardTheme(
          color: _lightCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _lightSurface,
          hintStyle: GoogleFonts.inter(color: _lightSubtitle),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD0D9E3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryTeal, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryTeal,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        extensions: const [_AppColors(subtitle: _lightSubtitle, card: _lightCard)],
      );
}

/// Custom theme extension to carry semantic colours.
@immutable
class _AppColors extends ThemeExtension<_AppColors> {
  const _AppColors({required this.subtitle, required this.card});

  final Color subtitle;
  final Color card;

  @override
  _AppColors copyWith({Color? subtitle, Color? card}) =>
      _AppColors(subtitle: subtitle ?? this.subtitle, card: card ?? this.card);

  @override
  _AppColors lerp(ThemeExtension<_AppColors>? other, double t) {
    if (other is! _AppColors) return this;
    return _AppColors(
      subtitle: Color.lerp(subtitle, other.subtitle, t)!,
      card: Color.lerp(card, other.card, t)!,
    );
  }
}

/// Helper extension so widgets can do `context.subtitleColor`.
extension AppThemeContext on BuildContext {
  Color get subtitleColor =>
      Theme.of(this).extension<_AppColors>()?.subtitle ?? Colors.grey;
  Color get cardColor =>
      Theme.of(this).extension<_AppColors>()?.card ?? Colors.grey.shade100;
}
