import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// App-wide configuration constants.
///
/// For local development: replace the placeholder strings below.
/// For CI/CD: inject via --dart-define at build time.
///   flutter run --dart-define=BACKEND_URL=https://my-api.onrender.com \
///               --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
class AppConfig {
  AppConfig._();

  // ── Flask backend ──────────────────────────────────────────────────────────
  static String get backendUrl {
    final String url = String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: kReleaseMode ? 'https://api.librisapp.com' : 'http://localhost:5000',
    );
    
    // Auto-detect Android Emulator
    if (!kIsWeb && 
        defaultTargetPlatform == TargetPlatform.android && 
        (url.contains('localhost') || url.contains('127.0.0.1'))) {
      return url.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
    }
    return url;
  }

  static const String librisApiKey = String.fromEnvironment(
    'LIBRIS_API_KEY',
    defaultValue: 'MhTxZ39Pl/mkP79ayEnmMrXIkVHuCQ/M1cBxTbeLrmd3i1wEpLFCNLZx7t0N+txP',
  );

  // ── Supabase ───────────────────────────────────────────────────────────────
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vnedgshbefpctjyzpqlm.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs',
  );

  // ── API paths ──────────────────────────────────────────────────────────────
  static const String apiBooks = '/api/books';
  static const String apiPopular = '/api/books/popular';
  static const String apiSearch = '/api/search';
  static const String apiRecommend = '/api/recommend';
  static const String apiTrack = '/api/track';

  // ── Misc ───────────────────────────────────────────────────────────────────
  static const String appName = 'Libris';
  static const String placeholderCover =
      'https://via.placeholder.com/120x180.png?text=Book';
}
