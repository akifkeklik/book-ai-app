import 'dart:async';
import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/supabase_service.dart';

class FavoritesProvider extends ChangeNotifier {
  final _svc = SupabaseService.instance;

  List<FavoriteBook> _favorites = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription<List<Map<String, dynamic>>>? _favoritesSub;

  List<FavoriteBook> get favorites => _favorites;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Set<String> get _favoriteIsbns => {for (final f in _favorites) f.isbn13};

  bool isFavorite(String isbn) => _favoriteIsbns.contains(isbn);

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> loadFavorites(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    _favoritesSub?.cancel();
    try {
      _favoritesSub = _svc.client
          .from('favorites')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('added_at', ascending: false)
          .listen((data) {
        _favorites = data.map((j) => FavoriteBook.fromJson(j)).toList();
        _isLoading = false;
        notifyListeners();
      }, onError: (e) {
        _error = 'Favoriler gerçek zamanlı güncellenemedi: $e';
        _isLoading = false;
        notifyListeners();
      });
    } catch (e) {
      _error = 'Failed to load favorites: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearFavorites() {
    _favoritesSub?.cancel();
    _favorites = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _favoritesSub?.cancel();
    super.dispose();
  }

  // ── Add / Remove ───────────────────────────────────────────────────────────

  Future<void> toggleFavorite({
    required String userId,
    required Book book,
  }) async {
    if (isFavorite(book.isbn13)) {
      await _removeFavorite(userId: userId, bookId: book.isbn13);
    } else {
      await _addFavorite(userId: userId, book: book);
    }
  }

  Future<void> removeFavoriteByBookId({
    required String userId,
    required String bookId,
  }) async {
    await _removeFavorite(userId: userId, bookId: bookId);
  }

  Future<void> removeFavoriteByIsbn({
    required String userId,
    required String isbn13,
  }) async {
    await _removeFavorite(userId: userId, bookId: isbn13);
  }

  Future<void> _addFavorite({required String userId, required Book book}) async {
    // Optimistic update
    final temp = FavoriteBook(
      id: '',
      userId: userId,
      isbn13: book.isbn13,
      bookTitle: book.title,
      thumbnail: book.thumbnail,
      addedAt: DateTime.now(),
    );
    _favorites.insert(0, temp);
    notifyListeners();

    try {
      await _svc.addFavorite(
        userId: userId,
        bookId: book.isbn13,
        title: book.title,
        author: book.author,
        imageUrl: book.thumbnail,
      );
      // Reload to get real ID
      await loadFavorites(userId);
    } catch (e) {
      // Rollback
      _favorites.removeWhere((f) => f.isbn13 == book.isbn13 && f.id.isEmpty);
      _error = 'Failed to add favorite.';
      notifyListeners();
    }
  }

  Future<void> _removeFavorite({
    required String userId,
    required String bookId,
  }) async {
    final removed = _favorites.firstWhere(
      (f) => f.isbn13 == bookId,
      orElse: () => FavoriteBook(
        id: '',
        userId: userId,
        isbn13: bookId,
        bookTitle: '',
        thumbnail: '',
        addedAt: DateTime.now(),
      ),
    );

    // Optimistic removal
    _favorites.removeWhere((f) => f.isbn13 == bookId);
    notifyListeners();

    try {
      await _svc.removeFavorite(userId, bookId);
    } catch (e) {
      // Rollback
      _favorites.insert(0, removed);
      _error = 'Failed to remove favorite.';
      notifyListeners();
    }
  }
}
