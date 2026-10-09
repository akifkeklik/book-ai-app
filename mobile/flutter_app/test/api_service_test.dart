import 'package:flutter_test/flutter_test.dart';
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
  group('ApiService Interceptors', () {
    test('interceptor adds Authorization header only if session is present', () async {
      final apiService = ApiService.instance;
      Session? currentSession;

      apiService.init(sessionProvider: () => currentSession);

      final dio = apiService.testDio;
      final interceptor = dio.interceptors.whereType<InterceptorsWrapper>().first;

      // --- Test 1: Null Session ---
      currentSession = null;
      var options = RequestOptions(path: '/test');
      var handler = FakeHandler();
      interceptor.onRequest.call(options, handler);
      expect(handler.capturedOptions?.headers.containsKey('Authorization'), isFalse);

      // --- Test 2: Dummy Session ---
      currentSession = Session(
        accessToken: 'dummy_token',
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

      options = RequestOptions(path: '/test');
      handler = FakeHandler();
      interceptor.onRequest.call(options, handler);
      expect(handler.capturedOptions?.headers['Authorization'], 'Bearer dummy_token');
    });
  });
}
