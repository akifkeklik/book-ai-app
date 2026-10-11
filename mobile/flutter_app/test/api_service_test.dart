import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/config.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';

// Fake RequestInterceptorHandler to capture the options
class FakeHandler extends RequestInterceptorHandler {
  RequestOptions? capturedOptions;

  @override
  void next(RequestOptions options) {
    capturedOptions = options;
    super.next(options);
  }
}

void main() {
  group('ApiService Interceptors and Auth Security', () {
    test('verifies JWT auth, anon key fallback, and absence of backend LIBRIS_API_KEY', () async {
      final apiService = ApiService.instance;
      Session? currentSession;

      // Initialize once with dynamic session provider
      apiService.init(sessionProvider: () => currentSession);

      final dio = apiService.testDio;
      final interceptor = dio.interceptors.whereType<InterceptorsWrapper>().first;

      // 1. Session is present -> Authorization Bearer with user JWT
      currentSession = Session(
        accessToken: 'user_jwt_token_123',
        expiresIn: 3600,
        tokenType: 'bearer',
        user: const User(
          id: 'user1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2023-01-01',
        ),
      );

      var options = RequestOptions(path: '/test');
      var handler = FakeHandler();
      interceptor.onRequest.call(options, handler);

      expect(handler.capturedOptions?.headers['Authorization'], 'Bearer user_jwt_token_123');
      expect(handler.capturedOptions?.headers.containsKey('X-Api-Key'), isFalse);

      // 2. Session is null -> Authorization Bearer with Supabase anon key
      currentSession = null;
      options = RequestOptions(path: '/test');
      handler = FakeHandler();
      interceptor.onRequest.call(options, handler);

      expect(handler.capturedOptions?.headers['Authorization'], 'Bearer ${AppConfig.supabaseAnonKey}');
      expect(handler.capturedOptions?.headers.containsKey('X-Api-Key'), isFalse);

      // 3. Shared backend LIBRIS_API_KEY is not in default headers or client config
      expect(dio.options.headers.containsKey('X-Api-Key'), isFalse);
    });
  });
}
