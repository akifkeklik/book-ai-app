import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  static const String _languageKey = 'preferred_language';
  
  Locale _locale = const Locale('en');
  Map<String, String> _localizedStrings = {};
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();

  Locale get locale => _locale;
  String get currentLanguageCode => _locale.languageCode;
  bool get isInitialized => _isInitialized;
  Future<void> get initialized => _initCompleter.future;

  LanguageProvider() {
    init();
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_languageKey);
      if (savedCode != null) {
        _locale = Locale(savedCode);
      }
      await loadTranslations();
      _isInitialized = true;
      _initCompleter.complete();
      notifyListeners();
    } catch (_) {
      await loadTranslations();
      _isInitialized = true;
      _initCompleter.complete();
      notifyListeners();
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (_locale.languageCode == languageCode) return;
    
    _locale = Locale(languageCode);
    await loadTranslations();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, languageCode);
    } catch (_) {
      // Ignore
    }
  }

  Future<void> loadTranslations() async {
    try {
      String jsonString = await rootBundle.loadString('assets/lang/${_locale.languageCode}.json');
      Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      _localizedStrings = jsonMap.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      _localizedStrings = {};
    }
  }

  String translate(String key, {Map<String, String>? args}) {
    String value = _localizedStrings[key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }

  /// Senior Solution: Localize dynamic genres from database
  String localizeGenre(String genre) {
    if (genre.isEmpty) return "";
    
    // Convert "Biography & Autobiography" -> "genre_biography_autobiography"
    final key = "genre_${genre.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_').replaceAll(RegExp(r'_+'), '_')}";
    
    // Remove trailing underscore if exists
    final cleanKey = key.endsWith('_') ? key.substring(0, key.length - 1) : key;
    
    if (_localizedStrings.containsKey(cleanKey)) {
      return _localizedStrings[cleanKey]!;
    }
    
    // Fallback: Title Case the raw string
    return genre.split(' ').map((word) {
      if (word.isEmpty) return "";
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Senior Solution: Localize relative date strings
  String formatRelativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    final isTr = _locale.languageCode == 'tr';

    if (diff.inDays > 30) return '${dt.day}/${dt.month}/${dt.year}';
    
    if (diff.inDays > 0) {
      return isTr ? '${diff.inDays} gün önce' : '${diff.inDays}d ago';
    }
    if (diff.inHours > 0) {
      return isTr ? '${diff.inHours} saat önce' : '${diff.inHours}h ago';
    }
    if (diff.inMinutes > 0) {
      return isTr ? '${diff.inMinutes} dakika önce' : '${diff.inMinutes}m ago';
    }
    
    return isTr ? 'az önce' : 'just now';
  }
}

// Extension to make it easier to access in build methods
extension AppLocalizations on BuildContext {
  String tr(String key, {Map<String, String>? args}) {
    return Provider.of<LanguageProvider>(this, listen: true).translate(key, args: args);
  }

  String trGenre(String genre) {
    return Provider.of<LanguageProvider>(this, listen: true).localizeGenre(genre);
  }

  String trRelativeDate(DateTime dt) {
    return Provider.of<LanguageProvider>(this, listen: true).formatRelativeDate(dt);
  }
}
