import 'dart:async';
import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/api_service.dart';

enum BookStatus { initial, loading, loaded, error }

class BookProvider extends ChangeNotifier {
  final _api = ApiService.instance;

  // ── Popular books ──────────────────────────────────────────────────────────
  List<Book> _popularBooks = [];
  BookStatus _popularStatus = BookStatus.initial;
  String? _popularError;

  List<Book> get popularBooks => _popularBooks;
  BookStatus get popularStatus => _popularStatus;
  String? get popularError => _popularError;

  // ── Search ─────────────────────────────────────────────────────────────────
  List<Book> _searchResults = [];
  BookStatus _searchStatus = BookStatus.initial;
  String? _searchError;
  String _lastQuery = '';

  List<Book> get searchResults => _searchResults;
  BookStatus get searchStatus => _searchStatus;
  String? get searchError => _searchError;
  String get lastQuery => _lastQuery;

  Timer? _debounce;

  // ── Init ───────────────────────────────────────────────────────────────────

  BookProvider() {
    _api.init();
    fetchPopular();
  }

  // ── Popular ────────────────────────────────────────────────────────────────

  Future<void> fetchPopular({int limit = 20}) async {
    if (_popularStatus == BookStatus.loading) return;
    _popularStatus = BookStatus.loading;
    _popularError = null;
    notifyListeners();
    try {
      _popularBooks = await _api.getPopularBooks(limit: limit);
      _popularStatus = BookStatus.loaded;
    } catch (e) {
      _popularError = _friendlyError(e);
      _popularStatus = BookStatus.error;
    }
    notifyListeners();
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  void searchDebounced(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => search(query));
  }

  Future<void> search(String query) async {
    if (query.trim() == _lastQuery) return;
    _lastQuery = query.trim();
    _searchStatus = BookStatus.loading;
    _searchError = null;
    notifyListeners();
    try {
      _searchResults = await _api.searchBooks(query.trim());
      _searchStatus = BookStatus.loaded;
    } catch (e) {
      _searchError = _friendlyError(e);
      _searchStatus = BookStatus.error;
    }
    notifyListeners();
  }

  void clearSearch() {
    _debounce?.cancel();
    _searchResults = [];
    _searchStatus = BookStatus.initial;
    _searchError = null;
    _lastQuery = '';
    notifyListeners();
  }

  // ── Recommendations ────────────────────────────────────────────────────────

  Future<List<Book>> getRecommendations(String bookTitle) async {
    return _api.getRecommendations(bookTitle);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') || msg.contains('connection')) {
      return 'Cannot reach server. Check your network or backend URL.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
