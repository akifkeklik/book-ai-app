import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'preferred_theme_color';
  static const String _modeKey = 'preferred_theme_mode';
  
  // ── Requested Accent Colors (Premium Shades) ──────────────────────────────
  static const Color red = Color(0xFFE57373);     // Soft Ruby
  static const Color blue = Color(0xFF64B5F6);    // Sky Azure
  static const Color green = Color(0xFF81C784);   // Sage Green
  static const Color yellow = Color(0xFFFFF176);  // Lemon Chiffon
  static const Color purple = Color(0xFFBA68C8);  // Lavender Mist

  Color _seedColor = blue; // Default to Blue
  ThemeMode _themeMode = ThemeMode.dark; // Default to Dark

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

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
        _themeMode = savedMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
      }
    } catch (_) {
      // Ignore errors for SharedPreferences
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
      await prefs.setString(_modeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) { /* ignore */ }
  }

  void toggleTheme() {
    setThemeMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
