import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:book_ai_app/providers/theme_provider.dart';
import 'package:book_ai_app/theme/design_system.dart';
import 'package:book_ai_app/theme/app_theme.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    DesignSystem.disableGoogleFontsInTests = true;
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('ThemeProvider & Design System Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('ThemeProvider initializes with default settings', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isDarkMode, true);
      expect(provider.palette, LibrisPalette.oceanBlue);
      expect(provider.textScaleFactor, 1.0);
      expect(provider.highContrast, false);
      expect(provider.reducedMotion, false);
      expect(provider.lineSpacing, 1.0);
      expect(provider.fontFamily, 'editorial');
    });

    test('ThemeProvider updates themeMode to light and system', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 20));

      await provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, ThemeMode.light);
      expect(provider.isDarkMode, false);

      await provider.setThemeMode(ThemeMode.system);
      expect(provider.themeMode, ThemeMode.system);
    });

    test('ThemeProvider updates palettes and sets matching primary seedColor', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 20));

      await provider.setPalette(LibrisPalette.lavender);
      expect(provider.palette, LibrisPalette.lavender);
      expect(provider.seedColor, LibrisPalette.lavender.primaryDark);

      await provider.setPalette(LibrisPalette.forestGreen);
      expect(provider.palette, LibrisPalette.forestGreen);
      expect(provider.seedColor, LibrisPalette.forestGreen.primaryDark);

      await provider.setPalette(LibrisPalette.oceanBlue);
      expect(provider.palette, LibrisPalette.oceanBlue);

      await provider.setPalette(LibrisPalette.terracotta);
      expect(provider.palette, LibrisPalette.terracotta);

      await provider.setPalette(LibrisPalette.amber);
      expect(provider.palette, LibrisPalette.amber);

      await provider.setPalette(LibrisPalette.turquoise);
      expect(provider.palette, LibrisPalette.turquoise);
    });

    test('ThemeProvider toggles accessibility flags: highContrast & reducedMotion', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 20));

      await provider.setHighContrast(true);
      expect(provider.highContrast, true);

      await provider.setReducedMotion(true);
      expect(provider.reducedMotion, true);

      await provider.setTextScaleFactor(1.15);
      expect(provider.textScaleFactor, 1.15);

      await provider.setLineSpacing(1.25);
      expect(provider.lineSpacing, 1.25);

      await provider.setFontFamily('serif');
      expect(provider.fontFamily, 'serif');
    });

    test('ThemeProvider safely restores saved preferences from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'preferred_theme_mode': 'light',
        'preferred_palette': 'terracotta',
        'preferred_high_contrast': true,
        'preferred_reduced_motion': true,
        'preferred_text_scale': 1.15,
        'preferred_line_spacing': 1.25,
        'preferred_font_family': 'serif',
      });

      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.themeMode, ThemeMode.light);
      expect(provider.palette, LibrisPalette.terracotta);
      expect(provider.highContrast, true);
      expect(provider.reducedMotion, true);
      expect(provider.textScaleFactor, 1.15);
      expect(provider.lineSpacing, 1.25);
      expect(provider.fontFamily, 'serif');
    });

    test('ThemeProvider gracefully handles legacy palette ids', () async {
      SharedPreferences.setMockInitialValues({
        'preferred_palette': 'peach',
      });

      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.palette, LibrisPalette.terracotta);
    });

    test('ThemeProvider is resilient against corrupted preference data', () async {
      SharedPreferences.setMockInitialValues({
        'preferred_theme_mode': 'invalid_mode_xyz',
        'preferred_palette': 'non_existent_palette',
        'preferred_text_scale': 99.9, // out of bounds
        'preferred_font_family': 'malicious_font_name',
      });

      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      // Defaults should be gracefully preserved
      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.palette, LibrisPalette.oceanBlue);
      expect(provider.textScaleFactor, 1.0);
      expect(provider.fontFamily, 'editorial');
    });

    test('AppTheme creates valid themes for all 6 palettes and high-contrast modes', () {
      for (final pal in LibrisPalette.values) {
        final dark = AppTheme.darkTheme(pal.primaryDark, palette: pal);
        expect(dark.brightness, Brightness.dark);
        expect(dark.scaffoldBackgroundColor, pal.backgroundDark);
        expect(dark.cardColor, pal.surfaceDark);

        final light = AppTheme.lightTheme(pal.primaryLight, palette: pal);
        expect(light.brightness, Brightness.light);
        expect(light.scaffoldBackgroundColor, pal.backgroundLight);
        expect(light.cardColor, pal.surfaceLight);

        // High contrast variant
        final darkHc = AppTheme.darkTheme(pal.primaryDark, palette: pal, highContrast: true);
        expect(darkHc.scaffoldBackgroundColor, const Color(0xFF000000));

        final lightHc = AppTheme.lightTheme(pal.primaryLight, palette: pal, highContrast: true);
        expect(lightHc.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      }
    });

    test('All 6 LibrisPalette definitions contain distinct non-null colors and ids', () {
      final ids = LibrisPalette.values.map((p) => p.id).toSet();
      expect(ids.length, 6);

      for (final p in LibrisPalette.values) {
        expect(p.primaryDark, isNotNull);
        expect(p.primaryLight, isNotNull);
        expect(p.backgroundDark, isNotNull);
        expect(p.backgroundLight, isNotNull);
        expect(p.surfaceDark, isNotNull);
        expect(p.surfaceLight, isNotNull);
        expect(p.accent, isNotNull);
        expect(p.translationKey.startsWith('palette_'), true);
      }
    });
  });
}
