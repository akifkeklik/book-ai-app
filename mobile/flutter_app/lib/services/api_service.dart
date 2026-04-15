import 'package:dio/dio.dart';

import '../config.dart';
import '../models/book_model.dart';

class ApiService {
  Future<List<String>> getCategories() async {
    final resp = await _dio.get(AppConfig.apiCategories);
    final List<dynamic> list =
        resp.data['categories'] as List<dynamic>? ?? const [];
    return list
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> getBooksByCategory(
      {required String category, int page = 1, int perPage = 40}) async {
    final resp = await _dio.get(
      AppConfig.apiBooks,
      queryParameters: {
        'category': category,
        'page': page,
        'per_page': perPage
      },
    );
    final List<dynamic> list = resp.data['books'] as List;
    return {
      'books':
          list.map((j) => Book.fromJson(j as Map<String, dynamic>)).toList(),
      'total': resp.data['total'],
      'total_pages': resp.data['total_pages'],
    };
  }

  ApiService._internal();
  static final ApiService instance = ApiService._internal();

  late final Dio _dio;

  void init() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': AppConfig.librisApiKey,
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // ignore: avoid_print
          print('[API] ${options.method} ${options.uri}');
          handler.next(options);
        },
        onError: (error, handler) {
          // ignore: avoid_print
          print('[API] Error: ${error.message}');
          handler.next(error);
        },
      ),
    );
  }

  // ── Books ──────────────────────────────────────────────────────────────────

  Future<List<Book>> getPopularBooks({int limit = 2000}) async {
    // Senior Update: Increased default limit to 2000
    final resp = await _dio.get(
      AppConfig.apiPopular,
      queryParameters: {'limit': limit},
    );
    final List<dynamic> list = resp.data['books'] as List;
    return list.map((j) => Book.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getAllBooks(
      {int page = 1, int perPage = 100}) async {
    // Senior Update: Increased perPage for faster discovery
    final resp = await _dio.get(
      AppConfig.apiBooks,
      queryParameters: {'page': page, 'per_page': perPage},
    );
    final List<dynamic> list = resp.data['books'] as List;
    return {
      'books':
          list.map((j) => Book.fromJson(j as Map<String, dynamic>)).toList(),
      'total': resp.data['total'],
      'total_pages': resp.data['total_pages'],
    };
  }

  Future<Book?> getBookByIsbn(String isbn) async {
    try {
      final resp = await _dio.get('/api/books/$isbn');
      return Book.fromJson(resp.data['book'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Future<List<Book>> searchBooks(String query, {int limit = 500}) async {
    // Senior Update: Increased limit for searches
    final resp = await _dio.get(
      AppConfig.apiSearch,
      queryParameters: {'q': query, 'limit': limit},
    );
    final List<dynamic> list = resp.data['books'] as List;
    return list.map((j) => Book.fromJson(j as Map<String, dynamic>)).toList();
  }

  // ── Recommendations ────────────────────────────────────────────────────────

  Future<List<Book>> getRecommendations(String bookTitle,
      {int topN = 20}) async {
    final resp = await _dio.get(
      AppConfig.apiRecommend,
      queryParameters: {'book': bookTitle, 'top_n': topN, 'hybrid': 'true'},
    );
    final List<dynamic> list = resp.data['recommendations'] as List;
    return list.map((j) => Book.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<Book>> getPersonalizedRecommendations(
      {required String userId}) async {
    try {
      final response = await _dio.get('/api/recommend/personalized',
          queryParameters: {'user_id': userId});
      if (response.data != null && response.data['recommendations'] != null) {
        return (response.data['recommendations'] as List)
            .map((json) => Book.fromJson(json))
            .toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[API] Personalized recommendations failed: $e');
    }
    return [];
  }

  Future<bool> submitOnboarding({
    required String userId,
    required List<String> bookIds,
    required List<String> genres,
  }) async {
    try {
      final response = await _dio.post('/api/onboarding', data: {
        'user_id': userId,
        'book_ids': bookIds,
        'genres': genres,
      });
      return response.data != null && response.data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    try {
      final response = await _dio.post('/api/feedback', data: {
        'user_id': userId,
        'book_id': bookId,
        'interaction': interaction,
      });
      return response.data != null && response.data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  // ── Activity tracking ──────────────────────────────────────────────────────

  Future<void> trackActivity({
    required String userId,
    required String bookName,
    String action = 'view',
  }) async {
    try {
      await _dio.post(
        AppConfig.apiTrack,
        data: {'user_id': userId, 'book_name': bookName, 'action': action},
      );
    } catch (_) {}
  }
}
