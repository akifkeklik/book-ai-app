import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/book_model.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';

enum BookStatus { initial, loading, loaded, error }

class BookProvider extends ChangeNotifier {
  final _api = ApiService.instance;
  final _supabase = SupabaseService.instance;

  // ── Popular / All Books ──────────────────────────────────────────────────
  List<Book> _rawPopularBooks = [];
  List<Book> _filteredPopularBooks = [];
  BookStatus _popularStatus = BookStatus.initial;
  String? _popularError;
  int _totalBooksCount = 0;
  DateTime? _lastFetchTime;
  bool _isLoadingMore = false;

  List<Book> get popularBooks => _filteredPopularBooks;
  List<Book> get allBooksDisplay => _filteredPopularBooks;
  BookStatus get popularStatus => _popularStatus;
  String? get popularError => _popularError;
  int get totalBooksCount => _totalBooksCount;
  bool get isLoadingMore => _isLoadingMore;

  // ── Personalized Recommendations ──────────────────────────────────────────
  List<Book> _personalizedRecs = [];
  BookStatus _personalizedStatus = BookStatus.initial;

  List<Book> get personalizedRecs => _personalizedRecs;
  BookStatus get personalizedStatus => _personalizedStatus;

  // ── Search & Filters ─────────────────────────────────────────────────────
  List<Book> _searchResults = [];
  BookStatus _searchStatus = BookStatus.initial;
  String? _searchError;
  String _lastQuery = '';

  // Filter state
  String _filterAuthor = '';
  int _filterPageRange = 0; // 0: All, 1: <300, 2: 300-500, 3: >500

  List<Book> get searchResults => _searchResults;
  BookStatus get searchStatus => _searchStatus;
  String? get searchError => _searchError;
  String get lastQuery => _lastQuery;
  String get filterAuthor => _filterAuthor;
  int get filterPageRange => _filterPageRange;

  Timer? _debounce;

  // ── Categories ──────────────────────────────────────────────────────────
  static const List<String> _fallbackGenres = [
    'Fiction',
    'Science',
    'History',
    'Mystery',
    'Fantasy',
    'Biography',
    'Self-Help',
    'Business',
    'Romance',
    'Thriller',
    'Philosophy',
    'Art',
    'Cooking',
    'Religion',
    'Computers',
    'Psychology',
    'Social Science',
    'Poetry',
    'Travel'
  ];

  List<String> _genres = List<String>.from(_fallbackGenres);
  List<String> get defaultGenres => _genres;

  BookProvider() {
    _api.init();
    _loadFromCache();
    // Senior Note: Removed fetchPopular from constructor to prevent
    // "building during build" errors. Initial fetch is now handled
    // by the screens or a dedicated initialization flow.
    _fetchTotalCount();
    fetchGenres();
  }

  Future<void> fetchGenres() async {
    try {
      final categories = await _api.getCategories();
      if (categories.isNotEmpty) {
        _genres = categories;
      } else {
        _genres = List<String>.from(_fallbackGenres);
      }
    } catch (_) {
      _genres = List<String>.from(_fallbackGenres);
    }
    notifyListeners();
  }

  Future<void> _fetchTotalCount() async {
    _totalBooksCount = await _supabase.getTotalBookCount();
    notifyListeners();
  }

  // ── Cache ────────────────────────────────────────────────────────────────
  void _loadFromCache() {
    final box = Hive.box('books_cache');
    final popularData = box.get('popular_books');
    if (popularData != null) {
      final List<dynamic> decoded = jsonDecode(popularData);
      _rawPopularBooks = decoded.map((j) => Book.fromJson(j)).toList();
      _applyGlobalFilters();
      _popularStatus = BookStatus.loaded;
    }
    notifyListeners();
  }

  void _saveToCache(String key, List<Book> books) {
    try {
      final box = Hive.box('books_cache');
      final encoded = jsonEncode(books.map((b) => b.toJson()).toList());
      box.put(key, encoded);
    } catch (_) {}
  }

  // ── Popular (Infinite Scroll) ───────────────────────────────────────────
  Future<void> fetchPopular({bool force = false}) async {
    if (!force &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inMinutes < 2) {
      return;
    }

    _popularStatus = BookStatus.loading;
    notifyListeners();

    try {
      List<Book> response;
      try {
        response = await _supabase.getPopularBooks(limit: 20);
      } catch (_) {
        // Fallback to Flask API when Supabase is unreachable or blocked by policy.
        response = await _api.getPopularBooks(limit: 20);
      }
      _rawPopularBooks = response;
      _applyGlobalFilters();
      _popularStatus = BookStatus.loaded;
      _lastFetchTime = DateTime.now();
      _saveToCache('popular_books', _rawPopularBooks);
      notifyListeners();
    } catch (e) {
      _popularStatus = BookStatus.error;
      _popularError = e.toString();
      notifyListeners();
    }
  }

  Future<void> fetchMorePopular() async {
    if (_isLoadingMore || _popularStatus != BookStatus.loaded) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final response = await _supabase.client
          .from('books')
          .select()
          .order('ratings_count', ascending: false)
          .range(_rawPopularBooks.length, _rawPopularBooks.length + 19)
          .timeout(const Duration(seconds: 10));

      final newBooks = (response as List).map((j) => Book.fromJson(j)).toList();
      _rawPopularBooks.addAll(newBooks);
      _applyGlobalFilters();
      _isLoadingMore = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching more books: $e');
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ── Personalized ─────────────────────────────────────────────────────────
  Future<void> fetchPersonalizedRecs(String userId,
      {bool force = false}) async {
    _personalizedStatus = BookStatus.loading;
    notifyListeners();
    try {
      _personalizedRecs =
          await _api.getPersonalizedRecommendations(userId: userId);

      if (_personalizedRecs.isEmpty ||
          _isTooSimilarToPopular(_personalizedRecs)) {
        debugPrint(
            'Personalized recs empty/similar to popular, trying fallback...');
        await _fetchFallbackRecommendations(userId);
      } else {
        _personalizedStatus = BookStatus.loaded;
      }
    } catch (e) {
      debugPrint('Personalized Recs error: $e. Using fallback...');
      await _fetchFallbackRecommendations(userId);
    }
    notifyListeners();
  }

  Future<void> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    // Optimistic UI: If dislike, remove from current recs immediately
    if (interaction == 'dislike') {
      _personalizedRecs.removeWhere((b) => b.isbn13 == bookId);
      notifyListeners();
    }

    try {
      final success = await _api.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: interaction,
      );

      if (success) {
        // Refresh recommendations in the background to reflect new affinity
        // We don't wait for this to finish to keep UI snappy
        fetchPersonalizedRecs(userId, force: true);
      }
    } catch (e) {
      debugPrint('Feedback submission error: $e');
    }
  }

  Future<bool> submitOnboarding({
    required String userId,
    required List<String> bookIds,
    required List<String> genres,
  }) async {
    try {
      final success = await _api.submitOnboarding(
        userId: userId,
        bookIds: bookIds,
        genres: genres,
      );
      if (success) {
        await fetchPersonalizedRecs(userId, force: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Onboarding submission error: $e');
      return false;
    }
  }

  Future<void> _fetchFallbackRecommendations(String userId) async {
    try {
      // 1) Seed from favorites and generate via API recommender.
      final favorites = await _supabase.getFavorites(userId);
      if (favorites.isEmpty) {
        _personalizedRecs = [];
        _personalizedStatus = BookStatus.loaded;
        return;
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
        var recs = recMap.values.toList();
        recs = _dropTopPopularDuplicates(recs);
        _personalizedRecs = recs.take(20).toList();
        _personalizedStatus = BookStatus.loaded;
        return;
      }

      // 2) Category-based fallback from first favorite's category.
      final firstFav = favorites.first;
      final bookId = (firstFav['book_id'] ?? '').toString();
      final bookData = await _supabase.getBookByIsbn(bookId);
      if (bookData != null && bookData.categories.isNotEmpty) {
        final category = bookData.primaryCategory;
        final response = await _api.getBooksByCategory(
          category: category,
          page: 1,
          perPage: 20,
        );
        final books = response['books'] as List<Book>;
        _personalizedRecs = _dropTopPopularDuplicates(books)
            .where((b) => !seedIds.contains(b.isbn13))
            .take(20)
            .toList();
      } else {
        _personalizedRecs = await _api.getPopularBooks(limit: 20);
      }

      _personalizedStatus = BookStatus.loaded;
    } catch (e) {
      debugPrint('Fallback Recs error: $e');
      _personalizedStatus = BookStatus.error;
    }
  }

  bool _isTooSimilarToPopular(List<Book> recs) {
    if (recs.isEmpty || _rawPopularBooks.isEmpty) return false;

    final recTop = recs.take(6).map((b) => b.isbn13).toList();
    final popTop = _rawPopularBooks.take(6).map((b) => b.isbn13).toList();
    if (recTop.length == popTop.length &&
        recTop.isNotEmpty &&
        List.generate(recTop.length, (i) => recTop[i] == popTop[i])
            .every((v) => v)) {
      return true;
    }

    final popSet = _rawPopularBooks.take(12).map((b) => b.isbn13).toSet();
    final overlap =
        recs.take(12).where((b) => popSet.contains(b.isbn13)).length;
    return overlap >= 10;
  }

  List<Book> _dropTopPopularDuplicates(List<Book> source) {
    if (_rawPopularBooks.isEmpty) return source;
    final popTopIds = _rawPopularBooks.take(8).map((b) => b.isbn13).toSet();
    final filtered =
        source.where((b) => !popTopIds.contains(b.isbn13)).toList();
    return filtered.isNotEmpty ? filtered : source;
  }

  // ── Search & Filter Logic ────────────────────────────────────────────────
  void search(String query) {
    _lastQuery = query;
    if (query.isEmpty) {
      _searchResults = [];
      _searchStatus = BookStatus.initial;
      notifyListeners();
      return;
    }
    _searchStatus = BookStatus.loading;
    notifyListeners();
    _performSearch(query);
  }

  void searchDebounced(String query) {
    _lastQuery = query;
    if (query.isEmpty) {
      _searchResults = [];
      _searchStatus = BookStatus.initial;
      notifyListeners();
      return;
    }
    _searchStatus = BookStatus.loading;
    notifyListeners();
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 500), () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    try {
      final results = await _supabase.searchBooks(query);
      _searchResults = results;
      _searchStatus = results.isEmpty ? BookStatus.initial : BookStatus.loaded;
    } catch (e) {
      _searchStatus = BookStatus.error;
      _searchError = e.toString();
    }
    notifyListeners();
  }

  void clearSearch() {
    _lastQuery = '';
    _searchResults = [];
    _searchStatus = BookStatus.initial;
    _searchError = null;
    notifyListeners();
  }

  void setFilters({String? author, int? pageRange}) {
    if (author != null) _filterAuthor = author;
    if (pageRange != null) _filterPageRange = pageRange;
    // In a real app, this would trigger a new search or filter.
    notifyListeners();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  void _applyGlobalFilters() {
    _filteredPopularBooks = List.from(_rawPopularBooks);
    notifyListeners();
  }
}
