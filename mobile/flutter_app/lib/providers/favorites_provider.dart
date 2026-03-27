import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/supabase_service.dart';

class FavoritesProvider extends ChangeNotifier {
  final _svc = SupabaseService.instance;

  List<FavoriteBook> _favorites = [];
  bool _isLoading = false;
  String? _error;

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
    try {
      _favorites = await _svc.getFavorites(userId);
    } catch (e) {
      _error = 'Failed to load favorites.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearFavorites() {
    _favorites = [];
    notifyListeners();
  }

  // ── Add / Remove ───────────────────────────────────────────────────────────

  Future<void> toggleFavorite({
    required String userId,
    required Book book,
  }) async {
    if (isFavorite(book.isbn13)) {
      await _removeFavorite(userId: userId, isbn13: book.isbn13);
    } else {
      await _addFavorite(userId: userId, book: book);
    }
  }

  /// Convenience method for screens that only have an isbn13 (e.g. favorites list).
  Future<void> removeFavoriteByIsbn({
    required String userId,
    required String isbn13,
  }) async {
    await _removeFavorite(userId: userId, isbn13: isbn13);
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
        isbn13: book.isbn13,
        bookTitle: book.title,
        thumbnail: book.thumbnail,
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
    required String isbn13,
  }) async {
    final removed = _favorites.firstWhere((f) => f.isbn13 == isbn13,
        orElse: () => FavoriteBook(
              id: '',
              userId: userId,
              isbn13: isbn13,
              bookTitle: '',
              thumbnail: '',
              addedAt: DateTime.now(),
            ));

    // Optimistic removal
    _favorites.removeWhere((f) => f.isbn13 == isbn13);
    notifyListeners();

    try {
      await _svc.removeFavorite(userId: userId, isbn13: isbn13);
    } catch (e) {
      // Rollback
      _favorites.insert(0, removed);
      _error = 'Failed to remove favorite.';
      notifyListeners();
    }
  }
}
