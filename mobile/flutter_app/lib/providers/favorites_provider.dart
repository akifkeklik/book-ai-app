import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/entities/book.dart';
import '../domain/entities/favorite_outbox_item.dart';
import '../data/models/book_dto.dart';
import '../data/repositories/favorites_outbox_repository.dart';
import '../services/supabase_service.dart';

class FavoritesProvider extends ChangeNotifier {
  final SupabaseService _svc;
  final FavoritesOutboxRepository _outboxRepo;

  List<FavoriteBook> _favorites = [];
  bool _isLoading = false;
  String? _error;
  String? _activeUserId;
  bool _isSyncing = false;
  StreamSubscription<List<Map<String, dynamic>>>? _favoritesSub;

  final Set<String> _pendingOperations = {};

  List<FavoriteBook> get favorites => _favorites;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  String? get activeUserId => _activeUserId;

  FavoritesProvider(this._svc, [FavoritesOutboxRepository? outboxRepo])
      : _outboxRepo = outboxRepo ?? FavoritesOutboxRepository();

  Set<String> get _favoriteIsbns => {for (final f in _favorites) f.isbn13};

  bool isFavorite(String isbn) => _favoriteIsbns.contains(isbn);

  bool isOperationPending(String isbn) => _pendingOperations.contains(isbn);

  bool hasPendingSync(String isbn) {
    if (_activeUserId == null) return false;
    return _outboxRepo.hasPendingItem(_activeUserId!, isbn);
  }

  OutboxStatus? getSyncStatus(String isbn) {
    if (_activeUserId == null) return null;
    return _outboxRepo.getItem(_activeUserId!, isbn)?.status;
  }

  int get pendingSyncCount {
    if (_activeUserId == null) return 0;
    return _outboxRepo.getPendingItems(_activeUserId!).length;
  }

  int get failedSyncCount {
    if (_activeUserId == null) return 0;
    return _outboxRepo
        .getPendingItems(_activeUserId!)
        .where((i) =>
            i.status == OutboxStatus.failed ||
            i.status == OutboxStatus.permanentFailure)
        .length;
  }

  bool get hasFailedSync => failedSyncCount > 0;

  bool _isNetworkOrOfflineError(dynamic error) {
    if (error == null) return false;
    final str = error.toString().toLowerCase();
    return str.contains('socketexception') ||
        str.contains('network') ||
        str.contains('offline') ||
        str.contains('timeout') ||
        str.contains('connection') ||
        str.contains('failed host lookup') ||
        str.contains('clientexception') ||
        str.contains('handshakeexception') ||
        str.contains('unreachable');
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> loadFavorites(String userId) async {
    _activeUserId = userId;
    _isLoading = true;
    _error = null;

    // Reset any items that were previously marked permanentFailure due to expired auth token
    _outboxRepo.resetAuthFailures(userId);

    // 1. Load cached snapshot from Hive for instant offline display
    final cached = _outboxRepo.getCachedFavorites(userId);
    if (cached.isNotEmpty) {
      _favorites = List.from(cached);
    } else {
      _favorites = [];
    }

    // 2. Overlay any pending outbox items on top of local cache
    _applyOutboxOverlay(userId);
    notifyListeners();

    // 3. Attempt quiet sync of pending outbox items
    _syncOutboxQuietly(userId);

    // 4. Listen to real Supabase stream
    _favoritesSub?.cancel();
    try {
      _favoritesSub = _svc.streamFavorites(userId).listen((data) {
        if (_activeUserId != userId) return;
        final serverFavs = data.map((j) => FavoriteBookDto.fromJson(j)).toList();
        // Persist fresh server snapshot to Hive cache
        _outboxRepo.saveFavoritesToCache(userId, serverFavs);

        _favorites = serverFavs;
        // Re-apply outbox overlay on top of fresh server data
        _applyOutboxOverlay(userId);
        _isLoading = false;
        notifyListeners();
      }, onError: (e) {
        if (_activeUserId != userId) return;
        _isLoading = false;
        if (_favorites.isEmpty) {
          _error = 'error_loading_books';
        }
        notifyListeners();
      });
    } catch (e) {
      _isLoading = false;
      if (_favorites.isEmpty) {
        _error = 'error_loading_books';
      }
      notifyListeners();
    }
  }

  void _applyOutboxOverlay(String userId) {
    final pendingItems = _outboxRepo.getPendingItems(userId);
    for (final item in pendingItems) {
      if (item.action == OutboxAction.add) {
        final exists = _favorites.any((f) => f.isbn13 == item.isbn13);
        if (!exists) {
          _favorites.insert(
            0,
            FavoriteBook(
              id: '', // Temporary pending identifier
              userId: item.userId,
              isbn13: item.isbn13,
              bookTitle: item.bookTitle,
              thumbnail: item.bookImageUrl ?? '',
              addedAt: item.createdAt,
            ),
          );
        }
      } else if (item.action == OutboxAction.remove) {
        _favorites.removeWhere((f) => f.isbn13 == item.isbn13);
      }
    }
  }

  Future<void> _syncOutboxQuietly(String userId) async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();
    try {
      final res = await _outboxRepo.syncUserOutbox(
        userId: userId,
        supabaseService: _svc,
      );
      if (res.synced > 0 || res.failed > 0) {
        _applyOutboxOverlay(userId);
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> retryFailedSync(String userId) async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();
    try {
      final res = await _outboxRepo.syncUserOutbox(
        userId: userId,
        supabaseService: _svc,
        forceRetry: true,
      );
      if (res.synced > 0 || res.failed > 0) {
        _applyOutboxOverlay(userId);
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  void clearFavorites() {
    _favoritesSub?.cancel();
    _favorites = [];
    _activeUserId = null;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _favoritesSub?.cancel();
    super.dispose();
  }

  // ── Add / Remove ───────────────────────────────────────────────────────────

  Future<void> toggleFavorite({
    required String userId,
    required Book book,
  }) async {
    if (_pendingOperations.contains(book.isbn13)) return;
    _pendingOperations.add(book.isbn13);
    try {
      if (isFavorite(book.isbn13)) {
        await _removeFavorite(userId: userId, bookId: book.isbn13);
      } else {
        await _addFavorite(userId: userId, book: book);
      }
    } finally {
      _pendingOperations.remove(book.isbn13);
    }
  }

  Future<void> removeFavoriteByIsbn({
    required String userId,
    required String isbn13,
  }) async {
    if (_pendingOperations.contains(isbn13)) return;
    _pendingOperations.add(isbn13);
    try {
      await _removeFavorite(userId: userId, bookId: isbn13);
    } finally {
      _pendingOperations.remove(isbn13);
    }
  }

  Future<void> _addFavorite({required String userId, required Book book}) async {
    final temp = FavoriteBook(
      id: '',
      userId: userId,
      isbn13: book.isbn13,
      bookTitle: book.title,
      thumbnail: book.thumbnail,
      addedAt: DateTime.now(),
    );

    // Optimistic update
    _favorites.insert(0, temp);
    notifyListeners();

    // Persist to Outbox before network call
    await _outboxRepo.enqueue(
      userId: userId,
      isbn13: book.isbn13,
      action: OutboxAction.add,
      bookTitle: book.title,
      bookAuthor: book.author,
      bookImageUrl: book.thumbnail,
    );
    notifyListeners();

    try {
      await _svc.addFavorite(
        userId: userId,
        bookId: book.isbn13,
        title: book.title,
        author: book.author,
        imageUrl: book.thumbnail,
      );

      // On network success: remove from outbox
      await _outboxRepo.removeItem(userId, book.isbn13);
      notifyListeners();
    } catch (e) {
      if (_isNetworkOrOfflineError(e)) {
        // Network/offline error: keep optimistic update pending in outbox for background sync
        notifyListeners();
      } else {
        // Permanent server rejection: remove from outbox and rollback
        await _outboxRepo.removeItem(userId, book.isbn13);
        _favorites.removeWhere((f) => f.isbn13 == book.isbn13 && f.id.isEmpty);
        _error = 'error';
        notifyListeners();
      }
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

    // Persist to Outbox before network call
    await _outboxRepo.enqueue(
      userId: userId,
      isbn13: bookId,
      action: OutboxAction.remove,
      bookTitle: removed.bookTitle,
      bookAuthor: '',
      bookImageUrl: removed.thumbnail,
    );
    notifyListeners();

    try {
      await _svc.removeFavorite(userId, bookId);

      // On network success: remove from outbox
      await _outboxRepo.removeItem(userId, bookId);
      notifyListeners();
    } catch (e) {
      if (_isNetworkOrOfflineError(e)) {
        // Network/offline error: keep optimistic removal pending in outbox for background sync
        notifyListeners();
      } else {
        // Permanent server rejection: remove from outbox and rollback
        await _outboxRepo.removeItem(userId, bookId);
        _favorites.insert(0, removed);
        _error = 'error';
        notifyListeners();
      }
    }
  }

  /// Clears in-memory favorite items, subscriptions, and active user session on logout.
  void clear() {
    _favoritesSub?.cancel();
    _favoritesSub = null;
    _favorites = [];
    _activeUserId = null;
    _error = null;
    _pendingOperations.clear();
    notifyListeners();
  }
}

