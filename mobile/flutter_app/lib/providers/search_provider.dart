import 'dart:async';
import 'package:flutter/material.dart';

import '../domain/entities/book.dart';
import '../domain/repositories/book_repository.dart';

enum SearchStatus { initial, loading, loaded, error }

class SearchProvider extends ChangeNotifier {
  final BookRepository _repository;

  SearchProvider({required BookRepository repository}) : _repository = repository;

  List<Book> _searchResults = [];
  SearchStatus _status = SearchStatus.initial;
  String? _error;
  String _lastQuery = '';
  Timer? _debounce;

  List<Book> get searchResults => _searchResults;
  SearchStatus get status => _status;
  String? get error => _error;
  String get lastQuery => _lastQuery;

  void search(String query) {
    _lastQuery = query;
    if (query.isEmpty) {
      _searchResults = [];
      _status = SearchStatus.initial;
      notifyListeners();
      return;
    }
    _status = SearchStatus.loading;
    notifyListeners();
    _performSearch(query);
  }

  void searchDebounced(String query) {
    _lastQuery = query;
    if (query.isEmpty) {
      _searchResults = [];
      _status = SearchStatus.initial;
      notifyListeners();
      return;
    }
    _status = SearchStatus.loading;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    try {
      final results = await _repository.searchBooks(query);
      _searchResults = results;
      _status = results.isEmpty ? SearchStatus.initial : SearchStatus.loaded;
    } catch (e) {
      _status = SearchStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  void clearSearch() {
    _lastQuery = '';
    _searchResults = [];
    _status = SearchStatus.initial;
    _error = null;
    notifyListeners();
  }
}
