import 'package:dio/dio.dart';

import '../config.dart';
import '../domain/entities/book.dart';
import '../domain/entities/learning_note.dart';
import '../domain/entities/learning_path.dart';
import '../domain/entities/knowledge_graph.dart';
import '../domain/entities/learning_outcome.dart';
import '../data/models/book_dto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  Future<List<Map<String, dynamic>>> getCategories() async {
    final resp = await _dio.get(AppConfig.apiCategories);
    final data = resp.data;
    if (data is Map<String, dynamic> && data['categories'] is List) {
      final list = data['categories'] as List;
      return list.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> chatWithAI(String query) async {
    try {
      final resp = await _dio.post(
        '/api/ai/chat',
        data: {'query': query},
        options: Options(
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      final data = resp.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      return const {
        'answer': 'Received an unexpected response from the AI assistant.',
        'referenced_books': <dynamic>[],
        'status': 'error',
      };
    } on DioException catch (e) {
      final msg = e.response?.data is Map && e.response?.data['error'] != null
          ? e.response!.data['error'].toString()
          : (e.message ?? 'Network error');
      return {
        'answer': msg,
        'referenced_books': <dynamic>[],
        'status': 'error',
        'error': msg,
      };
    } catch (e) {
      return {
        'answer': 'An unexpected error occurred: $e',
        'referenced_books': <dynamic>[],
        'status': 'error',
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> getBooksByCategory({
    required String category,
    int page = 1,
    int perPage = 40,
    String? sort,
    String? author,
    String? publisher,
    int? minPages,
    int? maxPages,
    double? minRating,
    int? publishedFrom,
    int? publishedTo,
  }) async {
    final resp = await _dio.get(
      AppConfig.apiBooks,
      queryParameters: {
        'category': category,
        'page': page,
        'per_page': perPage,
        if (sort != null) 'sort': sort,
        if (author != null) 'author': author,
        if (publisher != null) 'publisher': publisher,
        if (minPages != null) 'min_pages': minPages,
        if (maxPages != null) 'max_pages': maxPages,
        if (minRating != null) 'min_rating': minRating,
        if (publishedFrom != null) 'published_from': publishedFrom,
        if (publishedTo != null) 'published_to': publishedTo,
      },
    );
    final data = resp.data;
    if (data is Map<String, dynamic> && data['books'] is List) {
      final list = data['books'] as List;
      final books = list
          .whereType<Map<String, dynamic>>()
          .map((j) => BookDto.fromJson(j))
          .toList();
      return {
        'books': books,
        'total': data['total'] is int ? data['total'] : books.length,
        'total_pages': data['total_pages'] is int ? data['total_pages'] : 1,
      };
    }
    return {'books': <Book>[], 'total': 0, 'total_pages': 1};
  }

  ApiService._internal();
  static final ApiService instance = ApiService._internal();

  late Dio _dio;

  @visibleForTesting
  Dio get testDio => _dio;

  void init({Session? Function()? sessionProvider}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
        },
        // Accept all HTTP statuses so we can handle errors cleanly ourselves
        // (prevents Dio from throwing before we can inspect the response)
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          Session? session;
          try {
            session = sessionProvider != null
                ? sessionProvider()
                : Supabase.instance.client.auth.currentSession;
          } catch (_) {
            session = null;
          }
          if (session != null) {
            options.headers['Authorization'] = 'Bearer ${session.accessToken}';
          } else {
            options.headers['Authorization'] =
                'Bearer ${AppConfig.supabaseAnonKey}';
          }
          handler.next(options);
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
        onResponse: (response, handler) {
          final statusCode = response.statusCode ?? 0;
          if (statusCode >= 400) {
            final contentType = response.headers.value('content-type') ?? '';
            String message = 'Server returned HTTP $statusCode.';
            if (contentType.contains('text/html')) {
              message =
                  'Server returned HTTP $statusCode. Check backend configuration.';
            } else if (response.data is Map && response.data['error'] != null) {
              message = response.data['error'].toString();
            }
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                message: message,
              ),
            );
            return;
          }
          handler.next(response);
        },
        onError: (error, handler) {
          final msg = switch (error.type) {
            DioExceptionType.connectionTimeout ||
            DioExceptionType.sendTimeout ||
            DioExceptionType.receiveTimeout =>
              '[API] Timeout: ${error.requestOptions.uri}',
            DioExceptionType.connectionError =>
              '[API] Connection error — is the backend running? ${error.message}',
            DioExceptionType.badResponse =>
              '[API] Bad response (${error.response?.statusCode}): ${error.message}',
            _ => '[API] Error: ${error.message}',
          };
          // ignore: avoid_print
          print(msg);
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
    final data = resp.data;
    if (data is Map<String, dynamic> && data['books'] is List) {
      final list = data['books'] as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((j) => BookDto.fromJson(j))
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> getAllBooks(
      {int page = 1, int perPage = 100}) async {
    // Senior Update: Increased perPage for faster discovery
    final resp = await _dio.get(
      AppConfig.apiBooks,
      queryParameters: {'page': page, 'per_page': perPage},
    );
    final data = resp.data;
    if (data is Map<String, dynamic> && data['books'] is List) {
      final list = data['books'] as List;
      final books = list
          .whereType<Map<String, dynamic>>()
          .map((j) => BookDto.fromJson(j))
          .toList();
      return {
        'books': books,
        'total': data['total'] is int ? data['total'] : books.length,
        'total_pages': data['total_pages'] is int ? data['total_pages'] : 1,
      };
    }
    return {'books': <Book>[], 'total': 0, 'total_pages': 1};
  }

  Future<Book?> getBookByIsbn(String isbn) async {
    try {
      final resp = await _dio.get('/api/books/$isbn');
      final data = resp.data;
      if (data is Map<String, dynamic> && data['book'] is Map<String, dynamic>) {
        return BookDto.fromJson(data['book'] as Map<String, dynamic>);
      }
      return null;
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
    final data = resp.data;
    if (data is Map<String, dynamic> && data['books'] is List) {
      final list = data['books'] as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((j) => BookDto.fromJson(j))
          .toList();
    }
    return const [];
  }

  // ── Recommendations ────────────────────────────────────────────────────────

  Future<List<Book>> getRecommendations(String bookTitle,
      {int topN = 20}) async {
    final resp = await _dio.get(
      AppConfig.apiRecommend,
      queryParameters: {'book': bookTitle, 'top_n': topN, 'hybrid': 'true'},
    );
    final data = resp.data;
    if (data is Map<String, dynamic> && data['recommendations'] is List) {
      final list = data['recommendations'] as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((j) => BookDto.fromJson(j))
          .toList();
    }
    return const [];
  }

  Future<List<Book>> getPersonalizedRecommendations(
      {required String userId, int limit = 20, String? category, bool? excludeCompleted}) async {
    try {
      final queryParams = <String, dynamic>{
        'user_id': userId,
        'limit': limit,
      };
      if (category != null && category.trim().isNotEmpty) {
        queryParams['category'] = category.trim();
      }
      if (excludeCompleted == true) {
        queryParams['exclude_completed'] = 'true';
      }
      final response = await _dio.get('/api/recommend/personalized',
          queryParameters: queryParams);
      if (response.data != null && response.data['recommendations'] != null) {
        return (response.data['recommendations'] as List)
            .map((json) => BookDto.fromJson(json))
            .toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[API] Personalized recommendations failed: $e');
    }
    return [];
  }

  Future<bool> resetPersonalization({required String userId}) async {
    try {
      final response = await _dio.post('/api/preferences/reset', data: {'user_id': userId});
      return response.statusCode == 200 && response.data?['status'] == 'success';
    } catch (e) {
      // ignore: avoid_print
      print('[API] Reset personalization failed: $e');
      return false;
    }
  }

  Future<List<Book>> getLearningPathRecommendations({
    required String pathId,
    int limit = 10,
    bool excludeCompleted = true,
  }) async {
    try {
      final response = await _dio.get(
        '/api/learning-paths/$pathId/recommendations',
        queryParameters: {
          'limit': limit,
          'exclude_completed': excludeCompleted.toString(),
        },
      );
      if (response.data != null && response.data['recommendations'] != null) {
        return (response.data['recommendations'] as List)
            .map((json) => BookDto.fromJson(json))
            .toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[API] Learning path recommendations failed: $e');
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
    final response = await _dio.post('/api/feedback', data: {
      'user_id': userId,
      'book_id': bookId,
      'interaction': interaction,
    });
    return response.data != null && response.data['status'] == 'success';
  }

  // ── Activity tracking ──────────────────────────────────────────────────────

  Future<bool> trackActivity({
    required String userId,
    required String bookName,
    String? bookId,
    String action = 'view',
  }) async {
    try {
      final id = (bookId != null && bookId.isNotEmpty) ? bookId : bookName;
      final response = await _dio.post(
        AppConfig.apiTrack,
        data: {
          'user_id': userId,
          'book_id': id,
          'book_name': bookName,
          'action': action,
        },
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Taste Profile Preferences ──────────────────────────────────────────────

  Future<Map<String, dynamic>?> getUserPreferences({required String userId}) async {
    try {
      final response = await _dio.get('/api/preferences');
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[API] getUserPreferences error: $e');
    }
    return null;
  }

  Future<bool> updateUserPreferences({
    required String userId,
    required List<String> genres,
    List<String>? authors,
  }) async {
    try {
      final response = await _dio.put('/api/preferences', data: {
        'genres': genres,
        if (authors != null) 'authors': authors,
      });
      return response.statusCode == 200 ||
          (response.data is Map && response.data['status'] == 'success');
    } catch (e) {
      debugPrint('[API] updateUserPreferences error: $e');
      return false;
    }
  }

  // ── Library & Reading Journey ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getLibrary() async {
    try {
      final response = await _dio.get('/api/library');
      if (response.data is Map<String, dynamic> &&
          response.data['items'] is List) {
        final list = response.data['items'] as List;
        return list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('[API] getLibrary error: ');
    }
    return const [];
  }

  // ── Learning Notes & Knowledge Retention ───────────────────────────────────

  Future<List<LearningNote>> getNotes({
    String? bookId,
    String? noteType,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
        if (bookId != null && bookId.trim().isNotEmpty) 'book_id': bookId.trim(),
        if (noteType != null && noteType.trim().isNotEmpty) 'note_type': noteType.trim(),
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      };
      final response = await _dio.get('/api/notes', queryParameters: queryParams);
      if (response.data is Map<String, dynamic> && response.data['notes'] is List) {
        final list = response.data['notes'] as List;
        return list
            .whereType<Map<String, dynamic>>()
            .map((j) => LearningNote.fromJson(j))
            .toList();
      }
    } catch (e) {
      debugPrint('[API] getNotes error: $e');
    }
    return const [];
  }

  Future<LearningNote?> createNote({
    required String bookId,
    required String noteType,
    required String content,
    String? clientId,
  }) async {
    try {
      final response = await _dio.post('/api/notes', data: {
        'book_id': bookId,
        'note_type': noteType,
        'content': content,
        if (clientId != null && clientId.isNotEmpty) 'client_id': clientId,
      });
      if (response.data is Map<String, dynamic> && response.data['note'] is Map<String, dynamic>) {
        return LearningNote.fromJson(response.data['note'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[API] createNote error: $e');
    }
    return null;
  }

  Future<LearningNote?> updateNote({
    required String noteId,
    required String content,
    String? noteType,
  }) async {
    try {
      final response = await _dio.put('/api/notes/$noteId', data: {
        'content': content,
        if (noteType != null) 'note_type': noteType,
      });
      if (response.data is Map<String, dynamic> && response.data['note'] is Map<String, dynamic>) {
        return LearningNote.fromJson(response.data['note'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[API] updateNote error: $e');
    }
    return null;
  }

  Future<bool> deleteNote({required String noteId}) async {
    try {
      final response = await _dio.delete('/api/notes/$noteId');
      return response.statusCode == 200 ||
          (response.data is Map && response.data['deleted'] == true);
    } catch (e) {
      debugPrint('[API] deleteNote error: $e');
      return false;
    }
  }

  // ── Smart Review & Spaced Repetition ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getDueReviews({int limit = 50}) async {
    try {
      final response = await _dio.get(
        '/api/notes/reviews/due',
        queryParameters: {'limit': limit},
      );
      if (response.data is Map<String, dynamic> && response.data['reviews'] is List) {
        return List<Map<String, dynamic>>.from(response.data['reviews']);
      }
      return [];
    } catch (e) {
      debugPrint('[API] getDueReviews error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getReviewStats() async {
    try {
      final response = await _dio.get('/api/notes/reviews/stats');
      if (response.data is Map<String, dynamic> && response.data['stats'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(response.data['stats']);
      }
      return null;
    } catch (e) {
      debugPrint('[API] getReviewStats error: $e');
      return null;
    }
  }

  Future<bool> submitReview({required String noteId, required String outcome}) async {
    try {
      final response = await _dio.post(
        '/api/notes/$noteId/review',
        data: {'outcome': outcome},
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[API] submitReview error: $e');
      return false;
    }
  }

  Future<bool> updateReviewSettings({required String noteId, required String status}) async {
    try {
      final response = await _dio.put(
        '/api/notes/$noteId/review/settings',
        data: {'status': status},
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[API] updateReviewSettings error: $e');
      return false;
    }
  }

  // ── Notes Export ────────────────────────────────────────────────────────────

  Future<String?> exportNotesMarkdown({String? bookId}) async {
    try {
      final queryParams = <String, dynamic>{
        'format': 'markdown',
        if (bookId != null && bookId.isNotEmpty) 'book_id': bookId,
      };
      final response = await _dio.get(
        '/api/notes/export',
        queryParameters: queryParams,
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode == 200) {
        return response.data?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('[API] exportNotesMarkdown error: $e');
      return null;
    }
  }

  // ── Learning Paths & Progress Intelligence ──────────────────────────────────

  Future<List<LearningPath>> getLearningPaths({String? status}) async {
    try {
      final queryParams = <String, dynamic>{
        if (status != null && status.isNotEmpty) 'status': status,
      };
      final resp = await _dio.get('/api/learning-paths', queryParameters: queryParams);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['paths'] is List) {
        return (data['paths'] as List)
            .whereType<Map<String, dynamic>>()
            .map((p) => LearningPath.fromJson(p))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[API] getLearningPaths error: $e');
      return const [];
    }
  }

  Future<LearningPath?> getLearningPathDetail(String pathId) async {
    try {
      final resp = await _dio.get('/api/learning-paths/$pathId');
      final data = resp.data;
      if (data is Map<String, dynamic> && data['path'] is Map<String, dynamic>) {
        return LearningPath.fromJson(data['path'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] getLearningPathDetail error: $e');
      return null;
    }
  }

  Future<LearningPath?> createLearningPath({
    required String title,
    String? description,
    String? category,
    List<String>? bookIds,
  }) async {
    try {
      final payload = <String, dynamic>{
        'title': title.trim(),
        if (description != null && description.isNotEmpty) 'description': description.trim(),
        if (category != null && category.isNotEmpty) 'category': category.trim(),
        if (bookIds != null) 'book_ids': bookIds,
      };
      final resp = await _dio.post('/api/learning-paths', data: payload);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['path'] is Map<String, dynamic>) {
        return LearningPath.fromJson(data['path'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] createLearningPath error: $e');
      return null;
    }
  }

  Future<LearningPath?> updateLearningPath(
    String pathId, {
    String? title,
    String? description,
    String? category,
    String? status,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (title != null) 'title': title.trim(),
        if (description != null) 'description': description.trim(),
        if (category != null) 'category': category.trim(),
        if (status != null) 'status': status,
      };
      final resp = await _dio.put('/api/learning-paths/$pathId', data: payload);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['path'] is Map<String, dynamic>) {
        return LearningPath.fromJson(data['path'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] updateLearningPath error: $e');
      return null;
    }
  }

  Future<bool> deleteLearningPath(String pathId) async {
    try {
      final resp = await _dio.delete('/api/learning-paths/$pathId');
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('[API] deleteLearningPath error: $e');
      return false;
    }
  }

  Future<LearningPath?> addBookToLearningPath(String pathId, String bookId, {int? orderIndex}) async {
    try {
      final payload = <String, dynamic>{
        'book_id': bookId.trim(),
        if (orderIndex != null) 'order_index': orderIndex,
      };
      final resp = await _dio.post('/api/learning-paths/$pathId/books', data: payload);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['path'] is Map<String, dynamic>) {
        return LearningPath.fromJson(data['path'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] addBookToLearningPath error: $e');
      return null;
    }
  }

  Future<LearningPath?> removeBookFromLearningPath(String pathId, String bookId) async {
    try {
      final resp = await _dio.delete('/api/learning-paths/$pathId/books/${bookId.trim()}');
      final data = resp.data;
      if (data is Map<String, dynamic> && data['path'] is Map<String, dynamic>) {
        return LearningPath.fromJson(data['path'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] removeBookFromLearningPath error: $e');
      return null;
    }
  }

  Future<LearningPath?> reorderLearningPathBooks(String pathId, List<String> bookIds) async {
    try {
      final resp = await _dio.put(
        '/api/learning-paths/$pathId/reorder',
        data: {'book_ids': bookIds},
      );
      final data = resp.data;
      if (data is Map<String, dynamic> && data['path'] is Map<String, dynamic>) {
        return LearningPath.fromJson(data['path'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] reorderLearningPathBooks error: $e');
      return null;
    }
  }

  Future<List<Book>> getLearningPathSuggestions({
    String? category,
    String? query,
    int limit = 10,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        if (category != null && category.isNotEmpty) 'category': category,
        if (query != null && query.isNotEmpty) 'q': query,
        'limit': limit,
      };
      final resp = await _dio.get('/api/learning-paths/suggestions', queryParameters: queryParams);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['suggestions'] is List) {
        return (data['suggestions'] as List)
            .whereType<Map<String, dynamic>>()
            .map((b) => BookDto.fromJson(b))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[API] getLearningPathSuggestions error: $e');
      return const [];
    }
  }

  // ── Personal Knowledge Graph ───────────────────────────────────────────────

  Future<KnowledgeGraphData?> getKnowledgeGraph({
    String? focusId,
    int? depth,
    int? limit,
    String? type,
    String? relationshipType,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        if (focusId != null && focusId.isNotEmpty) 'focus_id': focusId,
        if (depth != null) 'depth': depth,
        if (limit != null) 'limit': limit,
        if (type != null && type.isNotEmpty) 'type': type,
        if (relationshipType != null && relationshipType.isNotEmpty) 'relationship_type': relationshipType,
      };
      final resp = await _dio.get('/api/knowledge-graph', queryParameters: queryParams);
      final data = resp.data;
      if (data is Map<String, dynamic>) {
        return KnowledgeGraphData.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('[API] getKnowledgeGraph error: $e');
      return null;
    }
  }

  Future<KnowledgeEdge?> createKnowledgeRelationship({
    required String sourceId,
    required String sourceType,
    required String targetId,
    required String targetType,
    required String relationshipType,
    String source = 'user_explicit',
    String? evidenceRef,
    String confidence = 'high',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final payload = <String, dynamic>{
        'source_id': sourceId,
        'source_type': sourceType,
        'target_id': targetId,
        'target_type': targetType,
        'relationship_type': relationshipType,
        'source': source,
        if (evidenceRef != null) 'evidence_ref': evidenceRef,
        'confidence': confidence,
        if (metadata != null) 'metadata': metadata,
      };
      final resp = await _dio.post('/api/knowledge-graph/relationships', data: payload);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['relationship'] is Map<String, dynamic>) {
        return KnowledgeEdge.fromJson(data['relationship'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] createKnowledgeRelationship error: $e');
      return null;
    }
  }

  Future<bool> deleteKnowledgeRelationship(String relationshipId) async {
    try {
      final resp = await _dio.delete('/api/knowledge-graph/relationships/$relationshipId');
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('[API] deleteKnowledgeRelationship error: $e');
      return false;
    }
  }

  Future<KnowledgeGraphData?> getNodeNeighbors(
    String nodeId, {
    int depth = 1,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'depth': depth,
        'limit': limit,
      };
      final resp = await _dio.get('/api/knowledge-graph/nodes/$nodeId/neighbors', queryParameters: queryParams);
      final data = resp.data;
      if (data is Map<String, dynamic>) {
        return KnowledgeGraphData.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('[API] getNodeNeighbors error: $e');
      return null;
    }
  }

  // ==========================================
  // SPRINT 28: LEARNING OUTCOMES INTELLIGENCE
  // ==========================================

  Future<LearningProgress?> getLearningOverview() async {
    try {
      final resp = await _dio.get('/api/learning/overview');
      final data = resp.data;
      if (data is Map<String, dynamic> && data['progress'] is Map<String, dynamic>) {
        return LearningProgress.fromJson(data['progress'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] getLearningOverview error: $e');
      return null;
    }
  }

  Future<List<ReviewItem>> getLearningQueue({
    String? concept,
    String? pathId,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        if (concept != null && concept.isNotEmpty) 'concept': concept,
        if (pathId != null && pathId.isNotEmpty) 'path_id': pathId,
      };
      final resp = await _dio.get('/api/learning/queue', queryParameters: queryParams);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['queue'] is List) {
        return (data['queue'] as List)
            .whereType<Map<String, dynamic>>()
            .map((j) => ReviewItem.fromJson(j))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[API] getLearningQueue error: $e');
      return const [];
    }
  }

  Future<ReviewItem?> getLearningItem(String itemId) async {
    try {
      final resp = await _dio.get('/api/learning/items/$itemId');
      final data = resp.data;
      if (data is Map<String, dynamic> && data['item'] is Map<String, dynamic>) {
        return ReviewItem.fromJson(data['item'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] getLearningItem error: $e');
      return null;
    }
  }

  Future<ReviewItem?> createLearningItem({
    required String title,
    required String concept,
    required String question,
    required String answer,
    String? explanation,
    String? bookId,
    String? pathId,
    String sourceType = 'custom_question',
    String? sourceId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'title': title,
        'concept': concept,
        'question': question,
        'answer': answer,
        if (explanation != null) 'explanation': explanation,
        if (bookId != null) 'book_id': bookId,
        if (pathId != null) 'path_id': pathId,
        'source_type': sourceType,
        if (sourceId != null) 'source_id': sourceId,
      };
      final resp = await _dio.post('/api/learning/items', data: payload);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['item'] is Map<String, dynamic>) {
        return ReviewItem.fromJson(data['item'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] createLearningItem error: $e');
      return null;
    }
  }

  Future<ReviewItem?> updateLearningItem(
    String itemId, {
    String? title,
    String? concept,
    String? question,
    String? answer,
    String? explanation,
    String? status,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (title != null) 'title': title,
        if (concept != null) 'concept': concept,
        if (question != null) 'question': question,
        if (answer != null) 'answer': answer,
        if (explanation != null) 'explanation': explanation,
        if (status != null) 'status': status,
      };
      final resp = await _dio.put('/api/learning/items/$itemId', data: payload);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['item'] is Map<String, dynamic>) {
        return ReviewItem.fromJson(data['item'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[API] updateLearningItem error: $e');
      return null;
    }
  }

  Future<bool> deleteLearningItem(String itemId) async {
    try {
      final resp = await _dio.delete('/api/learning/items/$itemId');
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('[API] deleteLearningItem error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> submitLearningAttempt({
    required String itemId,
    required String outcome,
    String responseText = '',
  }) async {
    try {
      final payload = <String, dynamic>{
        'outcome': outcome,
        'response_text': responseText,
      };
      final resp = await _dio.post('/api/learning/items/$itemId/attempt', data: payload);
      final data = resp.data;
      if (data is Map<String, dynamic>) {
        final attempt = data['attempt'] is Map<String, dynamic>
            ? ReviewAttempt.fromJson(data['attempt'] as Map<String, dynamic>)
            : null;
        final item = data['item'] is Map<String, dynamic>
            ? ReviewItem.fromJson(data['item'] as Map<String, dynamic>)
            : null;
        final schedule = data['schedule'] is Map<String, dynamic>
            ? data['schedule'] as Map<String, dynamic>
            : null;
        return {
          'attempt': attempt,
          'item': item,
          'schedule': schedule,
        };
      }
      return null;
    } catch (e) {
      debugPrint('[API] submitLearningAttempt error: $e');
      return null;
    }
  }

  Future<List<ReviewAttempt>> getLearningHistory({
    int limit = 50,
    int offset = 0,
    String? itemId,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
        if (itemId != null && itemId.isNotEmpty) 'item_id': itemId,
      };
      final resp = await _dio.get('/api/learning/history', queryParameters: queryParams);
      final data = resp.data;
      if (data is Map<String, dynamic> && data['history'] is List) {
        return (data['history'] as List)
            .whereType<Map<String, dynamic>>()
            .map((j) => ReviewAttempt.fromJson(j))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[API] getLearningHistory error: $e');
      return const [];
    }
  }

  Future<List<DifficultConcept>> getLearningConcepts() async {
    try {
      final resp = await _dio.get('/api/learning/concepts');
      final data = resp.data;
      if (data is Map<String, dynamic> && data['concepts'] is List) {
        return (data['concepts'] as List)
            .whereType<Map<String, dynamic>>()
            .map((j) => DifficultConcept.fromJson(j))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[API] getLearningConcepts error: $e');
      return const [];
    }
  }
}
