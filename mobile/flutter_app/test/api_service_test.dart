import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/config.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;
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

// Fake ResponseInterceptorHandler to capture response vs reject
class FakeResponseHandler extends ResponseInterceptorHandler {
  Response? capturedResponse;
  DioException? capturedError;

  @override
  void next(Response response) {
    capturedResponse = response;
  }

  @override
  void reject(DioException error, [bool callOnError = false]) {
    capturedError = error;
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

    test('onResponse rejects HTTP >= 400 with DioException badResponse and extracts error message', () {
      final apiService = ApiService.instance;
      apiService.init();

      final dio = apiService.testDio;
      // Second InterceptorsWrapper has onResponse
      final interceptor = dio.interceptors.whereType<InterceptorsWrapper>().elementAt(1);

      // 1. HTTP 200 -> passed through
      final reqOptions = RequestOptions(path: '/api/books');
      final resp200 = Response(
        requestOptions: reqOptions,
        statusCode: 200,
        data: {'books': []},
      );
      final handler200 = FakeResponseHandler();
      interceptor.onResponse.call(resp200, handler200);
      expect(handler200.capturedResponse, isNotNull);
      expect(handler200.capturedError, isNull);

      // 2. HTTP 404 with JSON error -> rejected as DioException with backend message
      final resp404 = Response(
        requestOptions: RequestOptions(path: '/api/books/12345'),
        statusCode: 404,
        data: {'error': 'Book not found'},
      );
      final handler404 = FakeResponseHandler();
      interceptor.onResponse.call(resp404, handler404);
      expect(handler404.capturedError, isNotNull);
      expect(handler404.capturedError?.type, DioExceptionType.badResponse);
      expect(handler404.capturedError?.message, 'Book not found');

      // 3. HTTP 429 Rate limited -> rejected with rate limit message
      final resp429 = Response(
        requestOptions: RequestOptions(path: '/api/ai/chat'),
        statusCode: 429,
        data: {'error': 'Rate limit exceeded. Please try again later.'},
      );
      final handler429 = FakeResponseHandler();
      interceptor.onResponse.call(resp429, handler429);
      expect(handler429.capturedError?.message, 'Rate limit exceeded. Please try again later.');

      // 4. HTTP 500 with HTML error -> rejected as badResponse with server error message
      final resp500 = Response(
        requestOptions: reqOptions,
        statusCode: 500,
        headers: Headers.fromMap({'content-type': ['text/html; charset=utf-8']}),
        data: '<html><body>500 Internal Server Error</body></html>',
      );
      final handler500 = FakeResponseHandler();
      interceptor.onResponse.call(resp500, handler500);
      expect(handler500.capturedError, isNotNull);
      expect(handler500.capturedError?.message, contains('Check backend configuration'));
    });
  });

  group('ApiService Payload Resilience', () {
    test('getCategories handles null or malformed response without crashing', () async {
      final apiService = ApiService.instance;
      apiService.init();
      apiService.testDio.httpClientAdapter = FakeHttpAdapter((opts) {
        return ResponseBody.fromString(
          jsonEncode({'categories': null}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final result = await apiService.getCategories();
      expect(result, isEmpty);
    });

    test('getPopularBooks handles null or non-list books without crashing', () async {
      final apiService = ApiService.instance;
      apiService.init();
      apiService.testDio.httpClientAdapter = FakeHttpAdapter((opts) {
        return ResponseBody.fromString(
          jsonEncode({'books': 'not-a-list'}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final result = await apiService.getPopularBooks();
      expect(result, isEmpty);
    });

    test('getRecommendations handles empty or malformed recommendations without throwing', () async {
      final apiService = ApiService.instance;
      apiService.init();
      apiService.testDio.httpClientAdapter = FakeHttpAdapter((opts) {
        return ResponseBody.fromString(
          jsonEncode({'recommendations': null}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final result = await apiService.getRecommendations('Dune');
      expect(result, isEmpty);
    });

    test('getBookByIsbn handles missing book object gracefully returning null', () async {
      final apiService = ApiService.instance;
      apiService.init();
      apiService.testDio.httpClientAdapter = FakeHttpAdapter((opts) {
        return ResponseBody.fromString(
          jsonEncode({'book': null}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final result = await apiService.getBookByIsbn('9780000000001');
      expect(result, isNull);
    });

    test('chatWithAI returns structured fallback on unexpected response body', () async {
      final apiService = ApiService.instance;
      apiService.init();
      apiService.testDio.httpClientAdapter = FakeHttpAdapter((opts) {
        return ResponseBody.fromString(
          'plain text non-json error',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/plain'],
          },
        );
      });

      final result = await apiService.chatWithAI('query');
      expect(result['status'], 'error');
      expect(result['referenced_books'], isEmpty);
    });
  });
}

class FakeHttpAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  FakeHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
