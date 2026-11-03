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
  bool _isFromCache = false;

  // Canonical fallback genres — derived from real dataset analysis (6,396 books).
  // These are the exact canonical names returned by the backend after normalization.
  // Order: by book count descending.
  static const List<String> _fallbackGenres = [
    'Fiction',
    'Biography & Memoir',
    'Young Adult & Children',
    'History',
    'Comics & Graphic Novels',
    'Business',
    'Psychology',
    'Education & Reference',
    'Health & Wellness',
    'Drama & Plays',
    'Philosophy',
    'Religion & Spirituality',
    'Poetry',
    'Science',
    'Social Sciences',
    'Art & Design',
    'Food & Cooking',
    'Self-Development',
    'Technology',
    'Travel',
    'Mystery & Thriller',
    'Humor & Satire',
    'Fantasy',
    'Science Fiction',
    'Horror',
    'Romance',
    'Sports & Games',
    'Crafts & Hobbies',
  ];

  List<String> _genres = List<String>.from(_fallbackGenres);

  // Filter state
  String _filterAuthor = '';
  int _filterPageRange = 0; // 0: All, 1: <300, 2: 300-500, 3: >500
  String _filterSearchQuery = '';
  String _filterCategory = '';
  String _sortBy = 'default'; // 'default', 'rating', 'pages', 'title'

  CatalogProvider({
    required ManageCatalogUseCase manageCatalog,
  }) : _manageCatalog = manageCatalog {
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
  bool get isFromCache => _isFromCache;
  bool get isOffline => _isFromCache;
  List<String> get defaultGenres => _genres;

  String get filterAuthor => _filterAuthor;
  int get filterPageRange => _filterPageRange;
  String get filterSearchQuery => _filterSearchQuery;
  String get filterCategory => _filterCategory;
  String get sortBy => _sortBy;
  bool get hasActiveFilters =>
      _filterAuthor.trim().isNotEmpty ||
      _filterPageRange != 0 ||
      _filterSearchQuery.trim().isNotEmpty ||
      _filterCategory.trim().isNotEmpty ||
      _sortBy != 'default';

  void _loadFromCache() {
    final cached = _manageCatalog.getCachedPopularBooks();
    if (cached.isNotEmpty) {
      _rawPopularBooks = cached;
      _applyGlobalFilters();
      _isFromCache = true;
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

  Map<String, int> _categoryCounts = {};

  Map<String, int> get categoryCounts => _categoryCounts;

  Future<void> fetchGenres() async {
    try {
      final categories = await _manageCatalog.getCategories();
      if (categories.isNotEmpty) {
        _genres = categories.map((e) => e['name']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        _categoryCounts = {
          for (var e in categories)
            if (e['name'] != null)
              e['name'].toString(): (e['count'] as num?)?.toInt() ?? 0
        };
      } else {
        _genres = List<String>.from(_fallbackGenres);
        _categoryCounts = {};
      }
    } catch (_) {
      _genres = List<String>.from(_fallbackGenres);
      _categoryCounts = {};
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
      _rawPopularBooks =
          await _manageCatalog.getPopularBooks(forceRefresh: force);
      _applyGlobalFilters();
      _isFromCache = false;
      _status = CatalogStatus.loaded;
      _error = null;
      _lastFetchTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      final cached = _manageCatalog.getCachedPopularBooks();
      if (cached.isNotEmpty) {
        _rawPopularBooks = cached;
        _applyGlobalFilters();
        _isFromCache = true;
        _status = CatalogStatus.loaded;
        _error = null;
      } else if (_rawPopularBooks.isNotEmpty) {
        _isFromCache = true;
        _status = CatalogStatus.loaded;
        _error = null;
      } else {
        _isFromCache = false;
        _status = CatalogStatus.error;
        _error = 'error_loading_books';
      }
      notifyListeners();
    }
  }

  Future<void> fetchMorePopular() async {
    if (_isLoadingMore || _status != CatalogStatus.loaded) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final newBooks = await _manageCatalog.getMorePopularBooks(
          offset: _rawPopularBooks.length, limit: 20);
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

  void setFilters({
    String? author,
    int? pageRange,
    String? searchQuery,
    String? category,
    String? sortBy,
  }) {
    if (author != null) _filterAuthor = author;
    if (pageRange != null) _filterPageRange = pageRange;
    if (searchQuery != null) _filterSearchQuery = searchQuery;
    if (category != null) _filterCategory = category;
    if (sortBy != null) _sortBy = sortBy;

    _applyGlobalFilters();
    notifyListeners();
  }

  void clearFilters() {
    _filterAuthor = '';
    _filterPageRange = 0;
    _filterSearchQuery = '';
    _filterCategory = '';
    _sortBy = 'default';

    _applyGlobalFilters();
    notifyListeners();
  }

  void _applyGlobalFilters() {
    Iterable<Book> result = _rawPopularBooks;

    // 1. Author Filter (case-insensitive substring)
    final authorQuery = _filterAuthor.trim().toLowerCase();
    if (authorQuery.isNotEmpty) {
      result = result.where((book) {
        return book.authors.toLowerCase().contains(authorQuery);
      });
    }

    // 2. Search Query (title or description or author)
    final textQuery = _filterSearchQuery.trim().toLowerCase();
    if (textQuery.isNotEmpty) {
      result = result.where((book) {
        return book.title.toLowerCase().contains(textQuery) ||
            book.authors.toLowerCase().contains(textQuery) ||
            book.description.toLowerCase().contains(textQuery);
      });
    }

    // 3. Category Filter
    final categoryQuery = _filterCategory.trim().toLowerCase();
    if (categoryQuery.isNotEmpty) {
      result = result.where((book) {
        return book.categories.toLowerCase().contains(categoryQuery);
      });
    }

    // 4. Page Range Filter (1: <300, 2: 300-500, 3: >500)
    if (_filterPageRange == 1) {
      result =
          result.where((book) => book.pageCount > 0 && book.pageCount < 300);
    } else if (_filterPageRange == 2) {
      result = result
          .where((book) => book.pageCount >= 300 && book.pageCount <= 500);
    } else if (_filterPageRange == 3) {
      result = result.where((book) => book.pageCount > 500);
    }

    // Materialize into a new list without mutating source catalog data
    final filtered = List<Book>.from(result);

    // 5. Sorting
    if (_sortBy == 'rating') {
      filtered.sort((a, b) => b.averageRating.compareTo(a.averageRating));
    } else if (_sortBy == 'pages') {
      filtered.sort((a, b) => a.pageCount.compareTo(b.pageCount));
    } else if (_sortBy == 'title') {
      filtered.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }

    _filteredPopularBooks = filtered;
  }
}
