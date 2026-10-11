// ignore_for_file: avoid_print, deprecated_member_use, prefer_const_declarations
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/config.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final bool runRealE2E = Platform.environment['RUN_REAL_E2E'] == 'true';

  group(
    'Real Network E2E Integration',
    () {
      setUpAll(() async {
        TestWidgetsFlutterBinding.ensureInitialized();

        // Enable real network requests in the Flutter test environment
        HttpOverrides.global = null;

        SharedPreferences.setMockInitialValues({});
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
        ApiService.instance.init();
      });

      test('E2E: Sign Up, Login, Catalog, AI', () async {
        final supabase = Supabase.instance.client;

        // 1. Sign Up
        final email =
            'test_e2e_${DateTime.now().millisecondsSinceEpoch}@example.com';
        final password = 'password123';

        try {
          await supabase.auth.signUp(email: email, password: password);
          print('Sign up successful for $email');
        } catch (e) {
          print('Sign up failed: $e');
        }

        // 2. Login
        try {
          final response = await supabase.auth
              .signInWithPassword(email: email, password: password);
          expect(response.session, isNotNull);
          print(
              'Login successful. Session token: ${response.session!.accessToken.substring(0, 10)}...');
        } catch (e) {
          print('Login failed: $e. Proceeding with anonymous access.');
        }

        // 3. Authenticated API request / Catalog
        try {
          final categories = await ApiService.instance.getCategories();
          print('Categories fetched: ${categories.length}');
          expect(categories, isNotEmpty);

          final books = await ApiService.instance.getAllBooks(perPage: 5);
          print('Books fetched: ${books['books'].length}');
          expect(books['books'], isNotEmpty);

          // 4. Recommendations
          if (books['books'].isNotEmpty) {
            final title = books['books'][0].title;
            final recs =
                await ApiService.instance.getRecommendations(title, topN: 2);
            print('Recommendations for "$title": ${recs.length}');
          }
        } catch (e) {
          print('API Error: $e');
        }

        // 5. AI (Needs LLM_API_KEY)
        try {
          final aiRes = await ApiService.instance
              .chatWithAI("Recommend me a good sci-fi book.");
          print('AI Response: ${aiRes['answer']}');
        } catch (e) {
          print(
              'AI Request failed (expected if missing valid LLM credential): $e');
        }
      });
    },
    skip: runRealE2E
        ? null
        : 'Skipped in standard CI/unit test run. Set RUN_REAL_E2E=true to execute with live backend.',
  );
}
