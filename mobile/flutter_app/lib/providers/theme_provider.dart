import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/design_system.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'preferred_theme_color';
  static const String _modeKey = 'preferred_theme_mode';
  static const String _textScaleKey = 'preferred_text_scale';
  static const String _paletteKey = 'preferred_palette';
  static const String _highContrastKey = 'preferred_high_contrast';
  static const String _reducedMotionKey = 'preferred_reduced_motion';
  static const String _lineSpacingKey = 'preferred_line_spacing';
  static const String _fontFamilyKey = 'preferred_font_family';

  // ── Backward Compatible Accent Colors ─────────────────────────────────────
  static const Color red = Color(0xFFE57373);     // Soft Ruby
  static const Color blue = Color(0xFF64B5F6);    // Sky Azure
  static const Color green = Color(0xFF81C784);   // Sage Green
  static const Color yellow = Color(0xFFFFF176);  // Lemon Chiffon
  static const Color purple = Color(0xFFBA68C8);  // Lavender Mist

  Color _seedColor = blue;
  ThemeMode _themeMode = ThemeMode.dark;
  double _textScaleFactor = 1.0;
  LibrisPalette _palette = LibrisPalette.oceanBlue;
  bool _highContrast = false;
  bool _reducedMotion = false;
  double _lineSpacing = 1.0;
  String _fontFamily = 'editorial';

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  double get textScaleFactor => _textScaleFactor;
  LibrisPalette get palette => _palette;
  bool get highContrast => _highContrast;
  bool get reducedMotion => _reducedMotion;
  double get lineSpacing => _lineSpacing;
  String get fontFamily => _fontFamily;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load Seed Color
      final savedColor = prefs.getInt(_themeKey);
      if (savedColor != null) {
        _seedColor = Color(savedColor);
      }

      // Load Theme Mode
      final savedMode = prefs.getString(_modeKey);
      if (savedMode != null) {
        if (savedMode == 'system') {
          _themeMode = ThemeMode.system;
        } else if (savedMode == 'light') {
          _themeMode = ThemeMode.light;
        } else {
          _themeMode = ThemeMode.dark;
        }
      }

      // Load Text Scale Factor
      final savedScale = prefs.getDouble(_textScaleKey);
      if (savedScale != null && savedScale >= 0.8 && savedScale <= 1.5) {
        _textScaleFactor = savedScale;
      }

      // Load Palette
      final savedPalette = prefs.getString(_paletteKey);
      if (savedPalette != null) {
        _palette = LibrisPalette.fromId(savedPalette);
      }

      // Load High Contrast
      final savedHc = prefs.getBool(_highContrastKey);
      if (savedHc != null) {
        _highContrast = savedHc;
      }

      // Load Reduced Motion
      final savedRm = prefs.getBool(_reducedMotionKey);
      if (savedRm != null) {
        _reducedMotion = savedRm;
      }

      // Load Line Spacing
      final savedLs = prefs.getDouble(_lineSpacingKey);
      if (savedLs != null && savedLs >= 0.8 && savedLs <= 2.0) {
        _lineSpacing = savedLs;
      }

      // Load Font Family
      final savedFf = prefs.getString(_fontFamilyKey);
      if (savedFf != null && (savedFf == 'editorial' || savedFf == 'serif' || savedFf == 'mono')) {
        _fontFamily = savedFf;
      }
    } catch (_) {
      // Safe fallback on SharedPreferences failure / corrupt data
    } finally {
      notifyListeners();
    }
  }

  Future<void> setSeedColor(Color color) async {
    if (_seedColor.value == color.value) return;
    _seedColor = color;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeKey, color.value);
    } catch (_) { /* ignore */ }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      String modeStr = 'dark';
      if (mode == ThemeMode.system) {
        modeStr = 'system';
      } else if (mode == ThemeMode.light) {
        modeStr = 'light';
      }
      await prefs.setString(_modeKey, modeStr);
    } catch (_) { /* ignore */ }
  }

  void toggleTheme() {
    setThemeMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> setTextScaleFactor(double scale) async {
    if (_textScaleFactor == scale) return;
    _textScaleFactor = scale;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_textScaleKey, scale);
    } catch (_) { /* ignore */ }
  }

  Future<void> setPalette(LibrisPalette newPalette) async {
    if (_palette == newPalette) return;
    _palette = newPalette;
    _seedColor = _themeMode == ThemeMode.light ? newPalette.primaryLight : newPalette.primaryDark;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_paletteKey, newPalette.id);
      await prefs.setInt(_themeKey, _seedColor.value);
    } catch (_) { /* ignore */ }
  }

  Future<void> setHighContrast(bool value) async {
    if (_highContrast == value) return;
    _highContrast = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_highContrastKey, value);
    } catch (_) { /* ignore */ }
  }

  Future<void> setReducedMotion(bool value) async {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_reducedMotionKey, value);
    } catch (_) { /* ignore */ }
  }

  Future<void> setLineSpacing(double value) async {
    if (_lineSpacing == value) return;
    _lineSpacing = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_lineSpacingKey, value);
    } catch (_) { /* ignore */ }
  }

  Future<void> setFontFamily(String family) async {
    if (_fontFamily == family) return;
    _fontFamily = family;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fontFamilyKey, family);
    } catch (_) { /* ignore */ }
  }
}
