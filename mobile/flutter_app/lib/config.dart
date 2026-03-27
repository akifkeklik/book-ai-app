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
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:5000', // Android emulator → localhost
  );

  // ── Supabase ───────────────────────────────────────────────────────────────
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR_PROJECT_ID.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY',
  );

  // ── API paths ──────────────────────────────────────────────────────────────
  static const String apiBooks = '/api/books';
  static const String apiPopular = '/api/books/popular';
  static const String apiSearch = '/api/search';
  static const String apiRecommend = '/api/recommend';
  static const String apiTrack = '/api/track';

  // ── Misc ───────────────────────────────────────────────────────────────────
  static const String appName = 'BookAI';
  static const String placeholderCover =
      'https://via.placeholder.com/120x180.png?text=Book';
}
