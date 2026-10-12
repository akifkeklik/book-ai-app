import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/config.dart';

void main() {
  group('AppConfig Hygiene and Safety', () {
    test('does not contain hardcoded active Supabase project credentials', () {
      expect(AppConfig.supabaseUrl, isNot(contains('vnedgshbefpctjyzpqlm')));
      expect(AppConfig.supabaseAnonKey, isNot(startsWith('eyJhbGciOiJIUzI1NiI')));
    });

    test('does not contain stale onrender fallback URL', () {
      expect(AppConfig.backendUrl, isNot(contains('book-ai-app-libris-api.onrender.com')));
    });

    test('defaults to localhost:5000 in local test/debug mode', () {
      expect(AppConfig.backendUrl, contains('5000'));
    });
  });
}
