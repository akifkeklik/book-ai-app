import 'package:flutter/foundation.dart';

/// Senior Solution: Centralized configuration with compile-time constants.
/// Using static const ensures these are resolved during compilation,
/// preventing "Unsupported operation" or "Bad state" errors in Flutter Web.
class AppConfig {
  AppConfig._();

  // ── Environment Variables ──────────────────────────────────────────────────

  static const String _envBackendUrl = String.fromEnvironment('BACKEND_URL');
  static const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envSupabaseKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _envApiKey = String.fromEnvironment('LIBRIS_API_KEY');

  // ── Flask Backend ──────────────────────────────────────────────────────────

  static String get backendUrl {
    if (_envBackendUrl.isNotEmpty) return _envBackendUrl;

    const String defaultUrl = kReleaseMode
        ? 'https://book-ai-app-libris-api.onrender.com'
        : 'http://localhost:5000';

    // Auto-detect Android Emulator
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        (defaultUrl.contains('localhost') ||
            defaultUrl.contains('127.0.0.1'))) {
      return defaultUrl
          .replaceAll('localhost', '10.0.2.2')
          .replaceAll('127.0.0.1', '10.0.2.2');
    }
    return defaultUrl;
  }

  static String get librisApiKey {
    if (_envApiKey.isNotEmpty) return _envApiKey;
    return 'MhTxZ39Pl/mkP79ayEnmMrXIkVHuCQ/M1cBxTbeLrmd3i1wEpLFCNLZx7t0N+txP';
  }

  // ── Supabase ───────────────────────────────────────────────────────────────

  static String get supabaseUrl {
    if (_envSupabaseUrl.isNotEmpty) return _envSupabaseUrl;
    return 'https://vnedgshbefpctjyzpqlm.supabase.co';
  }

  static String get supabaseAnonKey {
    if (_envSupabaseKey.isNotEmpty) return _envSupabaseKey;
    return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs';
  }

  // ── API Paths ──────────────────────────────────────────────────────────────

  static const String apiBooks = '/api/books';
  static const String apiCategories = '/api/categories';
  static const String apiPopular = '/api/books/popular';
  static const String apiSearch = '/api/search';
  static const String apiRecommend = '/api/recommend';
  static const String apiTrack = '/api/track';

  // ── Misc ───────────────────────────────────────────────────────────────────

  static const String appName = 'Libris';
  static const String placeholderCover =
      'https://via.placeholder.com/120x180.png?text=Book';
}
