import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  static const String _languageKey = 'preferred_language';
  static const List<String> supportedLanguages = ['en', 'tr', 'de'];

  static bool isSupported(String code) =>
      supportedLanguages.contains(code.toLowerCase());

  Locale _locale = const Locale('en');
  Map<String, String> _localizedStrings = {};
  Map<String, String> _fallbackStrings = {};
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
      if (savedCode != null && isSupported(savedCode)) {
        _locale = Locale(savedCode);
      } else {
        // Device language detection for first-time launch
        try {
          final deviceCode = WidgetsBinding
              .instance.platformDispatcher.locale.languageCode
              .toLowerCase();
          if (isSupported(deviceCode)) {
            _locale = Locale(deviceCode);
          } else {
            _locale = const Locale('en');
          }
        } catch (_) {
          _locale = const Locale('en');
        }
      }
      await loadTranslations();
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      notifyListeners();
    } catch (_) {
      try {
        final deviceCode = WidgetsBinding
            .instance.platformDispatcher.locale.languageCode
            .toLowerCase();
        if (isSupported(deviceCode)) {
          _locale = Locale(deviceCode);
        } else {
          _locale = const Locale('en');
        }
      } catch (_) {
        _locale = const Locale('en');
      }
      await loadTranslations();
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      notifyListeners();
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (!isSupported(languageCode)) return;
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
    // 1. Always load fallback (en.json) if not already en
    try {
      if (_locale.languageCode != 'en') {
        final enString = await rootBundle.loadString('assets/lang/en.json');
        final Map<String, dynamic> enMap = jsonDecode(enString);
        _fallbackStrings = enMap.map((k, v) => MapEntry(k, v.toString()));
      } else {
        _fallbackStrings = {};
      }
    } catch (_) {
      _fallbackStrings = {};
    }

    // 2. Load active locale strings
    try {
      final jsonString =
          await rootBundle.loadString('assets/lang/${_locale.languageCode}.json');
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      _localizedStrings =
          jsonMap.map((key, value) => MapEntry(key, value.toString()));
      if (_locale.languageCode == 'en') {
        _fallbackStrings = _localizedStrings;
      }
    } catch (e) {
      _localizedStrings = {};
    }
  }

  @visibleForTesting
  void setTranslationsForTest(
    String langCode,
    Map<String, String> strings, {
    Map<String, String>? fallback,
  }) {
    _locale = Locale(langCode);
    _localizedStrings = Map<String, String>.from(strings);
    _fallbackStrings = fallback != null
        ? Map<String, String>.from(fallback)
        : (_locale.languageCode == 'en' ? _localizedStrings : {});
    _isInitialized = true;
  }

  /// Global safeguard: transforms any missing or raw technical identifier into
  /// a safe, readable localized fallback so no snake_case key is ever displayed.
  String _safeguardFallback(String key) {
    final lower = key.toLowerCase().trim();

    // 1. Semantic action mappings for known product keys
    if (lower == 'manage_library' || lower == 'add_to_library') {
      return _locale.languageCode == 'tr'
          ? 'Kitaplığıma Ekle'
          : (_locale.languageCode == 'de'
              ? 'Zur Bibliothek hinzufügen'
              : 'Add to My Library');
    }
    if (lower == 'view_my_library' || lower == 'view_library') {
      return _locale.languageCode == 'tr'
          ? 'Kitaplığımı Görüntüle'
          : (_locale.languageCode == 'de'
              ? 'Meine Bibliothek öffnen'
              : 'View My Library');
    }
    if (lower == 'manage_shelf') {
      return _locale.languageCode == 'tr'
          ? 'Kitaplığımı Düzenle'
          : (_locale.languageCode == 'de'
              ? 'Bibliothek verwalten'
              : 'Manage Shelf');
    }
    if (lower == 'add_to_favorites') {
      return _locale.languageCode == 'tr'
          ? 'Favorilerime Ekle'
          : (_locale.languageCode == 'de'
              ? 'Zu Favoriten hinzufügen'
              : 'Add to Favorites');
    }
    if (lower == 'unfavorite' || lower == 'remove_from_favorites') {
      return _locale.languageCode == 'tr'
          ? 'Favorilerimden Kaldır'
          : (_locale.languageCode == 'de'
              ? 'Aus Favoriten entfernen'
              : 'Remove from Favorites');
    }
    if (lower == 'add_to_reading_list') {
      return _locale.languageCode == 'tr'
          ? 'Okuma Listeme Ekle'
          : (_locale.languageCode == 'de'
              ? 'Zur Leseliste hinzufügen'
              : 'Add to Reading List');
    }
    if (lower == 'update_failed') {
      return _locale.languageCode == 'tr'
          ? 'Durum güncellenemedi. Lütfen tekrar deneyin.'
          : (_locale.languageCode == 'de'
              ? 'Status konnte nicht aktualisiert werden. Bitte versuchen Sie es erneut.'
              : 'Failed to update status. Please try again.');
    }
    if (lower.startsWith('reason_')) {
      return _locale.languageCode == 'tr'
          ? 'Zevkinize göre önerildi'
          : (_locale.languageCode == 'de'
              ? 'Basierend auf Ihrem Geschmack'
              : 'Recommended for you');
    }
    if (lower.contains('error') || lower.contains('fail')) {
      return _locale.languageCode == 'tr'
          ? 'Bir hata oluştu. Lütfen tekrar deneyin.'
          : (_locale.languageCode == 'de'
              ? 'Ein Fehler ist aufgetreten. Bitte versuchen Sie es erneut.'
              : 'An error occurred. Please try again.');
    }

    // 2. If it is a snake_case technical identifier (contains '_'), humanize it:
    // e.g. 'unknown_key_name' -> 'Unknown Key Name'
    if (key.contains('_')) {
      return key
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
          .join(' ');
    }

    return key;
  }

  String translate(String key, {Map<String, String>? args}) {
    String? rawValue = _localizedStrings[key];
    if (rawValue == null || rawValue.isEmpty) {
      rawValue = _fallbackStrings[key];
    }

    String value = (rawValue != null && rawValue.isNotEmpty)
        ? rawValue
        : _safeguardFallback(key);

    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }

  /// Senior Solution: Pluralization support
  String plural(String key, int count, {Map<String, String>? args}) {
    String? rawValue;
    if (count == 1) {
      rawValue = _localizedStrings['${key}_one'] ??
          _fallbackStrings['${key}_one'] ??
          _localizedStrings[key] ??
          _fallbackStrings[key];
    } else {
      rawValue = _localizedStrings['${key}_other'] ??
          _fallbackStrings['${key}_other'] ??
          _localizedStrings[key] ??
          _fallbackStrings[key];
    }

    String value = (rawValue != null && rawValue.isNotEmpty)
        ? rawValue
        : _safeguardFallback(key);

    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    value = value.replaceAll('{count}', count.toString());
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
    if (_fallbackStrings.containsKey(cleanKey)) {
      return _fallbackStrings[cleanKey]!;
    }

    // Fallback: Clean Title Case without underscores
    return genre.replaceAll('_', ' ').split(' ').map((word) {
      if (word.isEmpty) return "";
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Senior Solution: Localize relative date strings
  String formatRelativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);

    if (diff.inDays > 30) return '${dt.day}/${dt.month}/${dt.year}';

    if (diff.inDays > 0) {
      return translate('time_day_ago', args: {'count': diff.inDays.toString()});
    }
    if (diff.inHours > 0) {
      return translate('time_hour_ago', args: {'count': diff.inHours.toString()});
    }
    if (diff.inMinutes > 0) {
      return translate('time_min_ago', args: {'count': diff.inMinutes.toString()});
    }

    return translate('time_just_now');
  }
}

// Extension to make it easier to access in build methods and async handlers safely
extension AppLocalizations on BuildContext {
  String tr(String key, {Map<String, String>? args, bool? listen}) {
    try {
      final shouldListen = listen ?? true;
      return Provider.of<LanguageProvider>(this, listen: shouldListen).translate(key, args: args);
    } catch (_) {
      return Provider.of<LanguageProvider>(this, listen: false).translate(key, args: args);
    }
  }

  String trPlural(String key, int count, {Map<String, String>? args, bool? listen}) {
    try {
      final shouldListen = listen ?? true;
      return Provider.of<LanguageProvider>(this, listen: shouldListen).plural(key, count, args: args);
    } catch (_) {
      return Provider.of<LanguageProvider>(this, listen: false).plural(key, count, args: args);
    }
  }

  String trGenre(String genre, {bool? listen}) {
    try {
      final shouldListen = listen ?? true;
      return Provider.of<LanguageProvider>(this, listen: shouldListen).localizeGenre(genre);
    } catch (_) {
      return Provider.of<LanguageProvider>(this, listen: false).localizeGenre(genre);
    }
  }

  String trRelativeDate(DateTime dt, {bool? listen}) {
    try {
      final shouldListen = listen ?? true;
      return Provider.of<LanguageProvider>(this, listen: shouldListen).formatRelativeDate(dt);
    } catch (_) {
      return Provider.of<LanguageProvider>(this, listen: false).formatRelativeDate(dt);
    }
  }
}
