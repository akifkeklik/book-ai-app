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

  // ── Flask Backend ──────────────────────────────────────────────────────────

  static String get backendUrl {
    if (_envBackendUrl.isNotEmpty) return _envBackendUrl;

    if (kReleaseMode) {
      throw StateError(
        'Missing required build-time configuration: BACKEND_URL must be specified via --dart-define=BACKEND_URL=https://your-api.domain.com in release builds.',
      );
    }

    const String defaultUrl = 'http://localhost:5000';

    // Auto-detect Android Emulator in local debug mode
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

  // ── Supabase ───────────────────────────────────────────────────────────────

  static String get supabaseUrl {
    if (_envSupabaseUrl.isNotEmpty) return _envSupabaseUrl;
    if (kReleaseMode) {
      throw StateError(
        'Missing required build-time configuration: SUPABASE_URL must be specified via --dart-define=SUPABASE_URL=https://your-project.supabase.co in release builds.',
      );
    }
    return 'https://placeholder.supabase.co';
  }

  static String get supabaseAnonKey {
    if (_envSupabaseKey.isNotEmpty) return _envSupabaseKey;
    if (kReleaseMode) {
      throw StateError(
        'Missing required build-time configuration: SUPABASE_ANON_KEY must be specified via --dart-define=SUPABASE_ANON_KEY=... in release builds.',
      );
    }
    return 'placeholder-anon-key';
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
      'https://placehold.co/120x180.png?text=Book';
}
