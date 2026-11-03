import 'dart:async';
import 'package:flutter/material.dart';

import '../domain/entities/book.dart';
import '../application/use_cases/search_books_use_case.dart';

enum SearchStatus { initial, loading, loaded, error }

class SearchProvider extends ChangeNotifier {
  final SearchBooksUseCase _searchBooksUseCase;

  SearchProvider({required SearchBooksUseCase searchBooksUseCase}) : _searchBooksUseCase = searchBooksUseCase;

  List<Book> _searchResults = [];
  SearchStatus _status = SearchStatus.initial;
  String? _error;
  String _lastQuery = '';
  Timer? _debounce;
  bool _isFromCache = false;

  List<Book> get searchResults => _searchResults;
  SearchStatus get status => _status;
  String? get error => _error;
  String get lastQuery => _lastQuery;
  bool get isFromCache => _isFromCache;
  bool get isOffline => _isFromCache;

  void search(String query) {
    _debounce?.cancel();
    _lastQuery = query;
    if (query.isEmpty) {
      _searchResults = [];
      _status = SearchStatus.initial;
      _error = null;
      _isFromCache = false;
      notifyListeners();
      return;
    }
    _status = SearchStatus.loading;
    _error = null;
    notifyListeners();
    _performSearch(query);
  }

  void searchDebounced(String query) {
    _lastQuery = query;
    _debounce?.cancel();
    if (query.isEmpty) {
      _searchResults = [];
      _status = SearchStatus.initial;
      _error = null;
      _isFromCache = false;
      notifyListeners();
      return;
    }
    _status = SearchStatus.loading;
    _error = null;
    notifyListeners();
    _debounce = Timer(const Duration(milliseconds: 500), () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    try {
      final results = await _searchBooksUseCase.execute(query);
      if (_lastQuery != query) return;
      _searchResults = results;
      _isFromCache = false;
      _status = SearchStatus.loaded;
      _error = null;
    } catch (e) {
      if (_lastQuery != query) return;
      final cached = _searchBooksUseCase.getCached(query);
      if (cached.isNotEmpty) {
        _searchResults = cached;
        _isFromCache = true;
        _status = SearchStatus.loaded;
        _error = null;
      } else {
        _searchResults = [];
        _isFromCache = false;
        _status = SearchStatus.error;
        _error = 'search_failed';
      }
    }
    notifyListeners();
  }

  void clearSearch() {
    _debounce?.cancel();
    _lastQuery = '';
    _searchResults = [];
    _status = SearchStatus.initial;
    _error = null;
    _isFromCache = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
