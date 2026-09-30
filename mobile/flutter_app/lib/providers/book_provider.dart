import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/entities/book.dart';
import '../domain/repositories/book_repository.dart';
import '../data/repositories/book_repository_impl.dart';
import '../application/use_cases/get_popular_books_use_case.dart';
import '../application/use_cases/get_personalized_recs_use_case.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';

enum BookStatus { initial, loading, loaded, error }

class BookProvider extends ChangeNotifier {
  late final BookRepository _repository;
  late final GetPopularBooksUseCase _getPopularBooks;
  late final GetPersonalizedRecsUseCase _getPersonalizedRecs;

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
  String? _lastPersonalizedUserId;

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
    // Inject dependencies
    _repository = BookRepositoryImpl(ApiService.instance, SupabaseService.instance);
    _getPopularBooks = GetPopularBooksUseCase(_repository);
    _getPersonalizedRecs = GetPersonalizedRecsUseCase(_repository);
    
    ApiService.instance.init();
    _loadFromCache();
    _fetchTotalCount();
    fetchGenres();
  }

  Future<void> fetchGenres() async {
    try {
      final categories = await _repository.getCategories();
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
    _totalBooksCount = await _repository.getTotalBookCount();
    notifyListeners();
  }

  // ── Cache ────────────────────────────────────────────────────────────────
  void _loadFromCache() {
    final cached = _repository.getCachedPopularBooks();
    if (cached.isNotEmpty) {
      _rawPopularBooks = cached;
      _applyGlobalFilters();
      _popularStatus = BookStatus.loaded;
    }
    notifyListeners();
  }

  // ── Popular (Infinite Scroll) ───────────────────────────────────────────
  Future<void> fetchPopular({bool force = false}) async {
    if (_popularStatus == BookStatus.loading) return;
    if (!force &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inMinutes < 2) {
      return;
    }

    _popularStatus = BookStatus.loading;
    notifyListeners();

    try {
      _rawPopularBooks = await _getPopularBooks.execute(forceRefresh: force);
      _applyGlobalFilters();
      _popularStatus = BookStatus.loaded;
      _lastFetchTime = DateTime.now();
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
      final newBooks = await _repository.getMorePopularBooks(offset: _rawPopularBooks.length, limit: 20);
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
    if (_personalizedStatus == BookStatus.loading && _lastPersonalizedUserId == userId) return;
    _lastPersonalizedUserId = userId;
    _personalizedStatus = BookStatus.loading;
    notifyListeners();
    try {
      final recs = await _getPersonalizedRecs.execute(userId, _rawPopularBooks);
      if (_lastPersonalizedUserId == userId) {
        _personalizedRecs = recs;
        _personalizedStatus = BookStatus.loaded;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Personalized Recs error: $e.');
      if (_lastPersonalizedUserId == userId) {
        _personalizedStatus = BookStatus.error;
        notifyListeners();
      }
    }
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
      final success = await _repository.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: interaction,
      );

      if (success) {
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
      final success = await _repository.submitOnboarding(
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
      final results = await _repository.searchBooks(query);
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
  }
}
