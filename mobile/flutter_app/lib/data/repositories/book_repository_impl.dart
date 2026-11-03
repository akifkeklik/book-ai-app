import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';
import '../../services/api_service.dart';
import '../../services/supabase_service.dart';
import '../models/book_dto.dart';

class BookRepositoryImpl implements BookRepository {
  final ApiService _api;
  final SupabaseService _supabase;
  final Box? _cacheBox;

  BookRepositoryImpl(this._api, this._supabase, [this._cacheBox]);

  Box? _getBox() {
    if (_cacheBox != null) return _cacheBox;
    if (Hive.isBoxOpen('books_cache')) {
      return Hive.box('books_cache');
    }
    return null;
  }

  String _normalizeQuery(String q) => q.trim().toLowerCase();

  @override
  Future<List<Book>> getPopularBooks({int limit = 20}) async {
    try {
      final books = await _supabase.getPopularBooks(limit: limit);
      if (books.isNotEmpty) {
        savePopularBooksToCache(books);
      }
      return books;
    } catch (_) {
      // Fallback to Flask API
      final books = await _api.getPopularBooks(limit: limit);
      if (books.isNotEmpty) {
        savePopularBooksToCache(books);
      }
      return books;
    }
  }

  @override
  Future<List<Book>> getMorePopularBooks(
      {required int offset, int limit = 20}) async {
    final response = await _supabase.client
        .from('books')
        .select()
        .order('ratings_count', ascending: false)
        .range(offset, offset + limit - 1)
        .timeout(const Duration(seconds: 10));

    return (response as List).map((j) => BookDto.fromJson(j)).toList();
  }

  @override
  Future<List<Book>> getPersonalizedRecommendations(String userId) async {
    return await _api.getPersonalizedRecommendations(userId: userId);
  }

  Future<List<Book>> getAdaptiveRecommendations({
    required String userId,
    String? category,
    bool? excludeCompleted,
  }) async {
    return await _api.getPersonalizedRecommendations(
      userId: userId,
      category: category,
      excludeCompleted: excludeCompleted,
    );
  }

  @override
  Future<List<Book>> getFallbackRecommendations(String userId) async {
    // 1) Seed from favorites
    final favorites = await _supabase.getFavorites(userId);
    if (favorites.isEmpty) {
      return [];
    }

    final seedIds = <String>[];
    final seedTitles = <String>[];
    for (final favorite in favorites.take(3)) {
      final bid = (favorite['book_id'] ?? '').toString();
      if (bid.isEmpty) continue;
      final book = await _supabase.getBookByIsbn(bid);
      if (book != null && book.title.isNotEmpty) {
        seedIds.add(book.isbn13);
        seedTitles.add(book.title);
      }
    }

    final recMap = <String, Book>{};
    for (final title in seedTitles) {
      final recs = await _api.getRecommendations(title, topN: 12);
      for (final rec in recs) {
        if (seedIds.contains(rec.isbn13)) continue;
        recMap.putIfAbsent(rec.isbn13, () => rec);
      }
    }

    if (recMap.isNotEmpty) {
      return recMap.values.take(20).toList();
    }

    // 2) Category fallback
    final firstFav = favorites.first;
    final bookId = (firstFav['book_id'] ?? '').toString();
    final bookData = await _supabase.getBookByIsbn(bookId);

    if (bookData != null && bookData.categories.isNotEmpty) {
      // UI Logic primaryCategory should be extracted
      final category = bookData.categories.split(RegExp(r'[|;,]')).first.trim();
      final response = await _api.getBooksByCategory(
        category: category,
        page: 1,
        perPage: 20,
      );
      final books = response['books'] as List<Book>;
      return books.where((b) => !seedIds.contains(b.isbn13)).take(20).toList();
    }

    return await _api.getPopularBooks(limit: 20);
  }

  @override
  Future<List<Book>> searchBooks(String query) async {
    final books = await _supabase.searchBooks(query);
    if (books.isNotEmpty) {
      saveSearchResultsToCache(query, books);
    }
    return books;
  }

  @override
  Future<List<Map<String, dynamic>>> getCategories() async {
    return await _api.getCategories();
  }

  @override
  Future<bool> submitFeedback(
      {required String userId,
      required String bookId,
      required String interaction}) async {
    return await _api.submitFeedback(
        userId: userId, bookId: bookId, interaction: interaction);
  }

  @override
  Future<bool> submitOnboarding(
      {required String userId,
      required List<String> bookIds,
      required List<String> genres}) async {
    return await _api.submitOnboarding(
        userId: userId, bookIds: bookIds, genres: genres);
  }

  @override
  List<Book> getCachedPopularBooks() {
    try {
      final box = _getBox();
      if (box == null) return [];
      final popularData = box.get('popular_books');
      if (popularData == null) return [];
      final dynamic decoded = jsonDecode(popularData.toString());
      if (decoded is! List) return [];
      final books = <Book>[];
      for (final item in decoded) {
        if (item is Map) {
          try {
            books.add(BookDto.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('Corrupt book item in popular_books cache: $e');
          }
        }
      }
      return books;
    } catch (e) {
      debugPrint('Cache read error (popular_books): $e');
      return [];
    }
  }

  @override
  void savePopularBooksToCache(List<Book> books) {
    try {
      final box = _getBox();
      if (box == null) return;
      final capped = books.take(50).toList();
      final encoded = jsonEncode(capped.map((b) => BookDto.toJson(b)).toList());
      box.put('popular_books', encoded).catchError((e) {
        debugPrint('Cache write async error (popular_books): $e');
      });
    } catch (e) {
      debugPrint('Cache write error (popular_books): $e');
    }
  }

  String _normalizeCategory(String category) {
    return category.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _touchLruKey(
    Box box,
    String keysKey,
    String normalizedKey, {
    int maxEntries = 30,
    String prefix = '',
  }) {
    try {
      List<String> keys = [];
      final rawKeys = box.get(keysKey);
      if (rawKeys is List) {
        keys = List<String>.from(rawKeys);
      } else if (rawKeys is String) {
        try {
          final decoded = jsonDecode(rawKeys);
          if (decoded is List) keys = List<String>.from(decoded);
        } catch (_) {}
      }

      keys.remove(normalizedKey);
      keys.add(normalizedKey);

      while (keys.length > maxEntries) {
        final oldest = keys.removeAt(0);
        if (prefix.isNotEmpty) {
          try {
            box.delete('$prefix$oldest').catchError((e) {
              debugPrint('Cache delete async error ($prefix$oldest): $e');
            });
          } catch (e) {
            debugPrint('Cache delete error ($prefix$oldest): $e');
          }
        }
      }

      try {
        box.put(keysKey, keys).catchError((e) {
          debugPrint('Cache write async error ($keysKey): $e');
        });
      } catch (e) {
        debugPrint('Cache write error ($keysKey): $e');
      }
    } catch (e) {
      debugPrint('LRU update error ($keysKey): $e');
    }
  }

  @override
  List<Book> getCachedSearchResults(String query) {
    final normalized = _normalizeQuery(query);
    if (normalized.isEmpty) return [];
    try {
      final box = _getBox();
      if (box == null) return [];
      final data = box.get('search_$normalized');
      if (data == null) return [];
      final dynamic decoded = jsonDecode(data.toString());
      if (decoded is! List) return [];
      final books = <Book>[];
      for (final item in decoded) {
        if (item is Map) {
          try {
            books.add(BookDto.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('Corrupt book item in search cache: $e');
          }
        }
      }
      if (books.isNotEmpty) {
        _touchLruKey(box, 'search_cache_keys', normalized,
            maxEntries: 30, prefix: 'search_');
      }
      return books;
    } catch (e) {
      debugPrint('Cache read error (search_$normalized): $e');
      return [];
    }
  }

  @override
  void saveSearchResultsToCache(String query, List<Book> books) {
    final normalized = _normalizeQuery(query);
    if (normalized.isEmpty || books.isEmpty) return;
    try {
      final box = _getBox();
      if (box == null) return;

      final capped = books.take(50).toList();
      final encoded = jsonEncode(capped.map((b) => BookDto.toJson(b)).toList());
      try {
        box.put('search_$normalized', encoded).catchError((e) {
          debugPrint('Cache write async error (search_$normalized): $e');
        });
      } catch (e) {
        debugPrint('Cache write error (search_$normalized): $e');
      }

      _touchLruKey(box, 'search_cache_keys', normalized,
          maxEntries: 30, prefix: 'search_');
    } catch (e) {
      debugPrint('Cache write error (search_$normalized): $e');
    }
  }

  Map<String, dynamic>? _getCachedCategoryData(String category) {
    final normalized = _normalizeCategory(category);
    if (normalized.isEmpty) return null;
    try {
      final box = _getBox();
      if (box == null) return null;
      final raw = box.get('category_$normalized');
      if (raw == null) return null;

      dynamic decoded;
      if (raw is String) {
        decoded = jsonDecode(raw);
      } else {
        decoded = raw;
      }

      List<dynamic>? bookList;
      int? total;
      int? totalPages;

      if (decoded is Map) {
        bookList = decoded['books'] as List<dynamic>?;
        total = decoded['total'] as int?;
        totalPages = decoded['total_pages'] as int?;
      } else if (decoded is List) {
        bookList = decoded;
        total = decoded.length;
        totalPages = 1;
      }

      if (bookList == null) return null;

      final books = <Book>[];
      for (final item in bookList) {
        if (item is Map) {
          try {
            books.add(BookDto.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('Corrupt book item in category cache ($normalized): $e');
          }
        }
      }

      if (books.isEmpty) return null;

      _touchLruKey(box, 'category_cache_keys', normalized,
          maxEntries: 25, prefix: 'category_');

      return {
        'books': books,
        'total': total ?? books.length,
        'total_pages': totalPages ?? 1,
      };
    } catch (e) {
      debugPrint('Cache read error (category_$normalized): $e');
      return null;
    }
  }

  @override
  List<Book> getCachedCategoryBooks(String category) {
    final data = _getCachedCategoryData(category);
    return data?['books'] as List<Book>? ?? [];
  }

  @override
  void saveCategoryBooksToCache(
    String category,
    List<Book> books, {
    int? total,
    int? totalPages,
  }) {
    final normalized = _normalizeCategory(category);
    if (normalized.isEmpty || books.isEmpty) return;
    try {
      final box = _getBox();
      if (box == null) return;

      final capped = books.take(50).toList();
      final payload = {
        'books': capped.map((b) => BookDto.toJson(b)).toList(),
        'total': total ?? books.length,
        'total_pages': totalPages ?? 1,
      };
      final encoded = jsonEncode(payload);

      try {
        box.put('category_$normalized', encoded).catchError((e) {
          debugPrint('Cache write async error (category_$normalized): $e');
        });
      } catch (e) {
        debugPrint('Cache write error (category_$normalized): $e');
      }

      _touchLruKey(box, 'category_cache_keys', normalized,
          maxEntries: 25, prefix: 'category_');
    } catch (e) {
      debugPrint('Cache write error (category_$normalized): $e');
    }
  }

  final Map<String, Future<Map<String, dynamic>>> _categoryInFlight = {};

  @override
  Future<int> getTotalBookCount() async {
    return await _supabase.getTotalBookCount();
  }

  @override
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
    final reqKey =
        '${_normalizeCategory(category)}_p${page}_pp${perPage}_s${sort}_a${author}_pub${publisher}_minP${minPages}_maxP${maxPages}_minR${minRating}_pf${publishedFrom}_pt$publishedTo';

    if (_categoryInFlight.containsKey(reqKey)) {
      return await _categoryInFlight[reqKey]!;
    }

    final future = _executeGetBooksByCategory(
      category: category,
      page: page,
      perPage: perPage,
      sort: sort,
      author: author,
      publisher: publisher,
      minPages: minPages,
      maxPages: maxPages,
      minRating: minRating,
      publishedFrom: publishedFrom,
      publishedTo: publishedTo,
    );

    _categoryInFlight[reqKey] = future;
    try {
      return await future;
    } finally {
      _categoryInFlight.remove(reqKey);
    }
  }

  Future<Map<String, dynamic>> _executeGetBooksByCategory({
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
    try {
      final response = await _api.getBooksByCategory(
        category: category,
        page: page,
        perPage: perPage,
        sort: sort,
        author: author,
        publisher: publisher,
        minPages: minPages,
        maxPages: maxPages,
        minRating: minRating,
        publishedFrom: publishedFrom,
        publishedTo: publishedTo,
      );

      final books = response['books'] as List<Book>? ?? [];
      final isDefaultFilter = (sort == null || sort == 'popularity') &&
          author == null &&
          publisher == null &&
          minPages == null &&
          maxPages == null &&
          minRating == null &&
          publishedFrom == null &&
          publishedTo == null;

      if (page == 1 && isDefaultFilter && books.isNotEmpty) {
        saveCategoryBooksToCache(
          category,
          books,
          total: response['total'] as int?,
          totalPages: response['total_pages'] as int?,
        );
      }

      return {
        ...response,
        'is_from_cache': false,
      };
    } catch (e) {
      if (page == 1) {
        final cachedData = _getCachedCategoryData(category);
        if (cachedData != null) {
          final books = cachedData['books'] as List<Book>;
          if (books.isNotEmpty) {
            return {
              'books': books,
              'total': cachedData['total'] ?? books.length,
              'total_pages': cachedData['total_pages'] ?? 1,
              'is_from_cache': true,
            };
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> chatWithAI(String query) async {
    return await _api.chatWithAI(query);
  }

  @override
  Future<List<Book>> getRecommendations(String title) async {
    return await _api.getRecommendations(title);
  }

  @override
  Future<void> trackActivity(
      {required String userId,
      required String activityType,
      required String bookId}) async {
    await _api.trackActivity(
      userId: userId,
      bookId: bookId,
      bookName: bookId,
      action: activityType,
    );
    await _supabase.trackActivity(
        userId: userId, activityType: activityType, bookId: bookId);
  }

  @override
  Future<Book?> getBookByIsbn(String isbn) async {
    Book? book = await _supabase.getBookByIsbn(isbn);
    book ??= await _api.getBookByIsbn(isbn);
    return book;
  }

  @override
  Future<String?> getUserInteraction(String userId, String bookId) async {
    return await _supabase.getUserInteraction(userId, bookId);
  }

  @override
  Future<void> upsertUserProfile({
    required String userId,
    required List<String> preferredGenres,
    required int readingFrequency,
    required List<String> preferredAuthors,
    required String preferredVibe,
  }) async {
    if (userId.trim().isEmpty) return;

    final profileData = {
      'user_id': userId,
      'preferred_genres': preferredGenres,
      'reading_frequency': readingFrequency,
      'preferred_authors': preferredAuthors,
      'preferred_vibe': preferredVibe,
      'updated_at': DateTime.now().toIso8601String(),
    };

    // 1. Optimistic offline-first local cache
    try {
      final box = _getBox();
      if (box != null) {
        await box.put('user_profile_$userId', jsonEncode(profileData));
      }
    } catch (e) {
      debugPrint('[BookRepositoryImpl] Local profile cache error: $e');
    }

    // 2. Persist to Supabase
    try {
      await _supabase.upsertUserProfile(
        userId: userId,
        preferredGenres: preferredGenres,
        readingFrequency: readingFrequency,
        preferredAuthors: preferredAuthors,
        preferredVibe: preferredVibe,
      );
    } catch (e) {
      debugPrint('[BookRepositoryImpl] Supabase profile upsert error: $e');
    }

    // 3. Sync to Flask API preferences if reachable
    try {
      await _api.updateUserPreferences(
        userId: userId,
        genres: preferredGenres,
        authors: preferredAuthors,
      );
    } catch (e) {
      debugPrint('[BookRepositoryImpl] Flask API profile update warning: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    if (userId.trim().isEmpty) return null;

    // 1. Try Supabase
    try {
      final remote = await _supabase.getUserProfile(userId);
      if (remote != null) {
        final profile = Map<String, dynamic>.from(remote);
        profile['is_from_cache'] = false;
        try {
          final box = _getBox();
          if (box != null) {
            await box.put('user_profile_$userId', jsonEncode(profile));
          }
        } catch (_) {}
        return profile;
      }
    } catch (e) {
      debugPrint('[BookRepositoryImpl] Supabase getUserProfile error: $e');
    }

    // 2. Try Flask API
    try {
      final apiPrefs = await _api.getUserPreferences(userId: userId);
      if (apiPrefs != null && apiPrefs['preferred_genres'] is List) {
        final profile = {
          'user_id': userId,
          'preferred_genres': apiPrefs['preferred_genres'],
          'preferred_authors': apiPrefs['preferred_authors'] ?? [],
          'reading_frequency': apiPrefs['reading_frequency'] ?? 2,
          'updated_at': apiPrefs['updated_at'],
          'is_from_cache': false,
        };
        try {
          final box = _getBox();
          if (box != null) {
            await box.put('user_profile_$userId', jsonEncode(profile));
          }
        } catch (_) {}
        return profile;
      }
    } catch (e) {
      debugPrint('[BookRepositoryImpl] Flask API getUserPreferences error: $e');
    }

    // 3. Fallback to local Hive cache for offline mode (explicitly tagged)
    try {
      final box = _getBox();
      if (box != null) {
        final raw = box.get('user_profile_$userId');
        if (raw != null) {
          final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
          Map<String, dynamic>? cachedMap;
          if (decoded is Map<String, dynamic>) {
            cachedMap = Map<String, dynamic>.from(decoded);
          } else if (decoded is Map) {
            cachedMap = Map<String, dynamic>.from(decoded);
          }
          if (cachedMap != null) {
            cachedMap['is_from_cache'] = true;
            return cachedMap;
          }
        }
      }
    } catch (e) {
      debugPrint('[BookRepositoryImpl] Cache read error for user_profile_$userId: $e');
    }

    return null;
  }

  @override
  void clearUserCache(String userId) {
    if (userId.trim().isEmpty) return;
    try {
      final box = _getBox();
      if (box != null) {
        box.delete('user_profile_$userId');
        box.delete('favorites_cache_$userId');
      }
    } catch (e) {
      debugPrint('[BookRepositoryImpl] clearUserCache error: $e');
    }
  }
}
