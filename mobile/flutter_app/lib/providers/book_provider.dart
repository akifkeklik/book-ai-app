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
  final List<String> _defaultGenres = [
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

  List<String> get defaultGenres => _defaultGenres;

  BookProvider() {
    _api.init();
    _loadFromCache();
    fetchPopular();
    _fetchTotalCount();
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
        DateTime.now().difference(_lastFetchTime!).inMinutes < 2) return;

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
          .range(_rawPopularBooks.length, _rawPopularBooks.length + 19);

      final newBooks = (response as List).map((j) => Book.fromJson(j)).toList();
      _rawPopularBooks.addAll(newBooks);
      _applyGlobalFilters();
      _isLoadingMore = false;
      notifyListeners();
    } catch (_) {
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
      _personalizedStatus = BookStatus.loaded;
    } catch (e) {
      _personalizedStatus = BookStatus.error;
    }
    notifyListeners();
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
