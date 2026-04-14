import 'package:flutter/material.dart';

/// A set of pastel seed colors to generate full Material 3 ColorSchemes.
class AppPastels {
  AppPastels._();

  static const Color dustyRose = Color(0xFFD49A89);
  static const Color oceanWhisper = Color(0xFF6B9E9E);
  static const Color sageGreen = Color(0xFF8B9E77);
  static const Color lavenderHaze = Color(0xFFA693B8);
  static const Color sandstone = Color(0xFFCBAD8D);
  static const Color slateBlue = Color(0xFF617A8C);

  /// Helper map to provide naming and iteration for Theme Picker UI
  static const Map<String, Color> themes = {
    'Dusty Rose': dustyRose,
    'Ocean Whisper': oceanWhisper,
    'Sage Green': sageGreen,
    'Lavender Haze': lavenderHaze,
    'Sandstone': sandstone,
    'Slate Blue': slateBlue,
  };

  /// Fallback colours to sequentially select for missing book covers
  static const List<Color> fallbackColors = [
    dustyRose,
    oceanWhisper,
    sageGreen,
    lavenderHaze,
    sandstone,
    slateBlue,
  ];

  /// Get a consistent colour based on a string (e.g. ISBN or Title)
  static Color getColorForString(String text) {
    if (text.isEmpty) return fallbackColors.first;
    int hash = text.hashCode;
    int index = hash.abs() % fallbackColors.length;
    return fallbackColors[index];
  }
}
