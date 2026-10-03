import 'dart:async';
import 'package:flutter/material.dart';

import '../domain/entities/book.dart';
import '../application/use_cases/manage_catalog_use_case.dart';

enum CatalogStatus { initial, loading, loaded, error }

class CatalogProvider extends ChangeNotifier {
  final ManageCatalogUseCase _manageCatalog;

  List<Book> _rawPopularBooks = [];
  List<Book> _filteredPopularBooks = [];
  CatalogStatus _status = CatalogStatus.initial;
  String? _error;
  int _totalBooksCount = 0;
  DateTime? _lastFetchTime;
  bool _isLoadingMore = false;

  // Canonical fallback genres — derived from real dataset analysis (6,396 books).
  // These are the exact canonical names returned by the backend after normalization.
  // Order: by book count descending.
  static const List<String> _fallbackGenres = [
    'Fiction',
    'Young Adult & Children',
    'History',
    'Drama & Plays',
    'Philosophy',
    'Religion & Spirituality',
    'Poetry',
    'Science',
    'Social Sciences',
    'Art & Design',
    'Food & Cooking',
    'Psychology',
    'Self-Development',
    'Technology',
    'Travel',
    'Mystery & Thriller',
    'Humor & Satire',
    'Fantasy',
    'Health & Wellness',
    'Biography & Memoir',
    'Science Fiction',
    'Horror',
    'Comics & Graphic Novels',
    'Romance',
    'Business',
  ];

  List<String> _genres = List<String>.from(_fallbackGenres);

  // Filter state
  String _filterAuthor = '';
  int _filterPageRange = 0; // 0: All, 1: <300, 2: 300-500, 3: >500

  CatalogProvider({
    required ManageCatalogUseCase manageCatalog,
  })  : _manageCatalog = manageCatalog {
    _loadFromCache();
    _fetchTotalCount();
    fetchGenres();
  }

  List<Book> get popularBooks => _filteredPopularBooks;
  List<Book> get allBooksDisplay => _filteredPopularBooks;
  CatalogStatus get status => _status;
  String? get error => _error;
  int get totalBooksCount => _totalBooksCount;
  bool get isLoadingMore => _isLoadingMore;
  List<String> get defaultGenres => _genres;

  String get filterAuthor => _filterAuthor;
  int get filterPageRange => _filterPageRange;

  void _loadFromCache() {
    final cached = _manageCatalog.getCachedPopularBooks();
    if (cached.isNotEmpty) {
      _rawPopularBooks = cached;
      _applyGlobalFilters();
      _status = CatalogStatus.loaded;
    }
    notifyListeners();
  }

  Future<void> _fetchTotalCount() async {
    try {
      _totalBooksCount = await _manageCatalog.getTotalBookCount();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchGenres() async {
    try {
      final categories = await _manageCatalog.getCategories();
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

  Future<void> fetchPopular({bool force = false}) async {
    if (_status == CatalogStatus.loading) return;
    if (!force &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inMinutes < 2) {
      return;
    }

    _status = CatalogStatus.loading;
    notifyListeners();

    try {
      _rawPopularBooks = await _manageCatalog.getPopularBooks(forceRefresh: force);
      _applyGlobalFilters();
      _status = CatalogStatus.loaded;
      _lastFetchTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      _status = CatalogStatus.error;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> fetchMorePopular() async {
    if (_isLoadingMore || _status != CatalogStatus.loaded) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final newBooks = await _manageCatalog.getMorePopularBooks(offset: _rawPopularBooks.length, limit: 20);
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

  void setFilters({String? author, int? pageRange}) {
    if (author != null) _filterAuthor = author;
    if (pageRange != null) _filterPageRange = pageRange;
    // In a real app, this would trigger a new search or filter.
    notifyListeners();
  }

  void _applyGlobalFilters() {
    _filteredPopularBooks = List.from(_rawPopularBooks);
  }
}
