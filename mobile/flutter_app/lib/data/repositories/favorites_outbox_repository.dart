import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../domain/entities/book.dart';
import '../../domain/entities/favorite_outbox_item.dart';
import '../../services/supabase_service.dart';
import '../models/book_dto.dart';

class SyncResult {
  final int synced;
  final int failed;
  final int skipped;

  const SyncResult({
    required this.synced,
    required this.failed,
    required this.skipped,
  });

  @override
  String toString() => 'SyncResult(synced: $synced, failed: $failed, skipped: $skipped)';
}

class FavoritesOutboxRepository {
  final Box? _injectedBox;
  final Set<String> _syncingUsers = {};

  static const int maxItemsPerUser = 100;
  static const int maxRetentionDays = 30;

  FavoritesOutboxRepository([this._injectedBox]);

  Box? _getBox() {
    if (_injectedBox != null) return _injectedBox;
    if (Hive.isBoxOpen('favorites_outbox')) {
      return Hive.box('favorites_outbox');
    }
    if (Hive.isBoxOpen('books_cache')) {
      return Hive.box('books_cache');
    }
    return null;
  }

  String _buildKey(String userId, String isbn13) => 'outbox_${userId}_$isbn13';

  // ── Outbox Item Management ──────────────────────────────────────────────────

  FavoriteOutboxItem? getItem(String userId, String isbn13) {
    try {
      final box = _getBox();
      if (box == null) return null;
      final raw = box.get(_buildKey(userId, isbn13));
      if (raw == null) return null;

      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      FavoriteOutboxItem? item;
      if (decoded is Map<String, dynamic>) {
        item = FavoriteOutboxItem.fromJson(decoded);
      } else if (decoded is Map) {
        item = FavoriteOutboxItem.fromJson(Map<String, dynamic>.from(decoded));
      }
      if (item != null && !_syncingUsers.contains(userId) && item.status == OutboxStatus.syncing) {
        return item.copyWith(status: OutboxStatus.pending);
      }
      return item;
    } catch (e) {
      debugPrint('Error reading outbox item ($userId, $isbn13): $e');
      return null;
    }
  }

  bool hasPendingItem(String userId, String isbn13) {
    return getItem(userId, isbn13) != null;
  }

  List<FavoriteOutboxItem> getPendingItems(String userId) {
    try {
      final box = _getBox();
      if (box == null) return [];

      final prefix = 'outbox_${userId}_';
      final items = <FavoriteOutboxItem>[];

      for (final key in box.keys) {
        if (key.toString().startsWith(prefix)) {
          final raw = box.get(key);
          if (raw == null) continue;
          try {
            final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
            if (decoded is Map<String, dynamic>) {
              items.add(FavoriteOutboxItem.fromJson(decoded));
            } else if (decoded is Map) {
              items.add(FavoriteOutboxItem.fromJson(Map<String, dynamic>.from(decoded)));
            }
          } catch (e) {
            debugPrint('Corrupt outbox entry for key $key: $e');
          }
        }
      }

      // Recover any orphaned in-flight items that were stuck in syncing after a crash
      if (!_syncingUsers.contains(userId)) {
        for (int i = 0; i < items.length; i++) {
          if (items[i].status == OutboxStatus.syncing) {
            final recovered = items[i].copyWith(status: OutboxStatus.pending);
            items[i] = recovered;
            box.put(_buildKey(userId, recovered.isbn13), jsonEncode(recovered.toJson())).catchError((e) {
              debugPrint('Error persisting recovered outbox item: $e');
            });
          }
        }
      }

      // FIFO order
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return items;
    } catch (e) {
      debugPrint('Error loading pending items for user $userId: $e');
      return [];
    }
  }

  Future<void> enqueue({
    required String userId,
    required String isbn13,
    required OutboxAction action,
    required String bookTitle,
    required String bookAuthor,
    required String? bookImageUrl,
  }) async {
    final box = _getBox();
    if (box == null) return;

    // Prune stale records if capacity exceeded
    _pruneOldItems(userId, box);

    final existing = getItem(userId, isbn13);
    final key = _buildKey(userId, isbn13);

    // Coalescing: Check whether desired final state matches server baseline state
    if (existing != null && existing.action != action) {
      final serverHasBook = getCachedFavorites(userId).any((f) => f.isbn13 == isbn13);
      final desiredStateMatchesServer =
          (action == OutboxAction.add && serverHasBook) ||
          (action == OutboxAction.remove && !serverHasBook);

      if (desiredStateMatchesServer) {
        // If desired final state already matches what is on server, cancel both out (net zero operation)
        await removeItem(userId, isbn13);
        return;
      }
      // Otherwise, server state is opposite of user's new action, so proceed to enqueue the new action
    }

    // Coalesce into desired final state
    final item = FavoriteOutboxItem(
      id: '${userId}_$isbn13',
      userId: userId,
      isbn13: isbn13,
      action: action,
      bookTitle: bookTitle.isNotEmpty ? bookTitle : (existing?.bookTitle ?? ''),
      bookAuthor: bookAuthor.isNotEmpty ? bookAuthor : (existing?.bookAuthor ?? ''),
      bookImageUrl: bookImageUrl ?? existing?.bookImageUrl,
      createdAt: existing?.createdAt ?? DateTime.now(),
      retryCount: 0, // Reset retries on explicit user interaction
      status: OutboxStatus.pending,
      lastError: null,
      lastAttemptAt: null,
      nextAttemptAt: null,
    );

    try {
      await box.put(key, jsonEncode(item.toJson()));
    } catch (e) {
      debugPrint('Error saving outbox item $key: $e');
      rethrow;
    }
  }

  Future<void> removeItem(String userId, String isbn13) async {
    try {
      final box = _getBox();
      if (box == null) return;
      await box.delete(_buildKey(userId, isbn13));
    } catch (e) {
      debugPrint('Error removing outbox item ($userId, $isbn13): $e');
    }
  }

  Future<void> updateItem(FavoriteOutboxItem item) async {
    try {
      final box = _getBox();
      if (box == null) return;
      await box.put(_buildKey(item.userId, item.isbn13), jsonEncode(item.toJson()));
    } catch (e) {
      debugPrint('Error updating outbox item ${item.id}: $e');
    }
  }

  Future<void> markFailed(String userId, String isbn13, String error) async {
    final existing = getItem(userId, isbn13);
    if (existing == null) return;

    final nextRetry = existing.retryCount + 1;
    final backoffSeconds = (1 << nextRetry).clamp(2, 300);

    final updated = existing.copyWith(
      status: OutboxStatus.failed,
      retryCount: nextRetry,
      lastError: error,
      lastAttemptAt: DateTime.now(),
      nextAttemptAt: DateTime.now().add(Duration(seconds: backoffSeconds)),
    );
    await updateItem(updated);
  }

  void resetAuthFailures(String userId) {
    try {
      final box = _getBox();
      if (box == null) return;
      final items = getPendingItems(userId);
      for (final item in items) {
        if (item.status == OutboxStatus.permanentFailure &&
            _isAuthRecoverable((item.lastError ?? '').toLowerCase())) {
          final reset = item.copyWith(
            status: OutboxStatus.pending,
            retryCount: 0,
            clearLastError: true,
            clearNextAttemptAt: true,
          );
          box.put(_buildKey(userId, reset.isbn13), jsonEncode(reset.toJson())).catchError((_) {});
        }
      }
    } catch (e) {
      debugPrint('Error resetting auth failures for user $userId: $e');
    }
  }

  void _pruneOldItems(String userId, Box box) {
    try {
      final items = getPendingItems(userId);
      final now = DateTime.now();

      // 1. Remove permanent failures older than maxRetentionDays
      for (final item in items) {
        if (item.status == OutboxStatus.permanentFailure &&
            now.difference(item.createdAt).inDays > maxRetentionDays) {
          box.delete(_buildKey(item.userId, item.isbn13));
        }
      }

      // 2. Capacity cap: Prioritize evicting permanent failures, then high-retry failed items, protecting active user edits
      if (items.length >= maxItemsPerUser) {
        final toEvictCount = items.length - maxItemsPerUser + 1;
        final candidates = List<FavoriteOutboxItem>.from(items);
        candidates.sort((a, b) {
          int rank(FavoriteOutboxItem item) {
            if (item.status == OutboxStatus.permanentFailure) return 0;
            if (item.status == OutboxStatus.failed) return 1;
            return 2;
          }
          final rDiff = rank(a).compareTo(rank(b));
          if (rDiff != 0) return rDiff;
          if (a.status == OutboxStatus.failed && b.status == OutboxStatus.failed) {
            return b.retryCount.compareTo(a.retryCount);
          }
          return a.createdAt.compareTo(b.createdAt);
        });

        for (final item in candidates.take(toEvictCount)) {
          box.delete(_buildKey(item.userId, item.isbn13));
        }
      }
    } catch (_) {}
  }

  // ── Sync Execution ──────────────────────────────────────────────────────────

  bool isSyncing(String userId) => _syncingUsers.contains(userId);

  Future<SyncResult> syncUserOutbox({
    required String userId,
    required SupabaseService supabaseService,
    bool forceRetry = false,
  }) async {
    if (_syncingUsers.contains(userId)) {
      return const SyncResult(synced: 0, failed: 0, skipped: 0);
    }
    _syncingUsers.add(userId);

    int synced = 0;
    int failed = 0;
    int skipped = 0;

    try {
      final items = getPendingItems(userId);
      for (final item in items) {
        // Skip permanent failures unless explicitly forcing retry
        if (item.status == OutboxStatus.permanentFailure && !forceRetry) {
          skipped++;
          continue;
        }

        // Max retries check (5 attempts)
        if (item.retryCount >= 5 && !forceRetry) {
          await updateItem(item.copyWith(
            status: OutboxStatus.permanentFailure,
            lastError: 'Max retries (5) exceeded.',
          ));
          skipped++;
          continue;
        }

        // Exponential backoff check
        if (!forceRetry &&
            item.status == OutboxStatus.failed &&
            item.nextAttemptAt != null &&
            DateTime.now().isBefore(item.nextAttemptAt!)) {
          skipped++;
          continue;
        }

        // Mark syncing
        await updateItem(item.copyWith(status: OutboxStatus.syncing));

        try {
          if (item.action == OutboxAction.add) {
            await supabaseService.addFavorite(
              userId: item.userId,
              bookId: item.isbn13,
              title: item.bookTitle,
              author: item.bookAuthor,
              imageUrl: item.bookImageUrl,
            );
          } else {
            await supabaseService.removeFavorite(item.userId, item.isbn13);
          }

          // Successfully synced: remove from outbox
          await removeItem(item.userId, item.isbn13);
          synced++;
        } catch (e) {
          failed++;
          final errStr = e.toString().toLowerCase();

          if (_isAuthError(errStr)) {
            // 401/403/JWT expired: Permanent failure, abort sync loop for this user
            await updateItem(item.copyWith(
              status: OutboxStatus.permanentFailure,
              lastError: 'Auth error (401/403): $e',
              lastAttemptAt: DateTime.now(),
            ));
            break;
          } else if (_isValidationError(errStr)) {
            await updateItem(item.copyWith(
              status: OutboxStatus.permanentFailure,
              lastError: 'Validation error: $e',
              lastAttemptAt: DateTime.now(),
            ));
          } else {
            // Transient network error
            final nextRetry = item.retryCount + 1;
            final isPermanent = nextRetry >= 5;
            final backoffSeconds = (1 << nextRetry).clamp(2, 300);
            await updateItem(item.copyWith(
              status: isPermanent
                  ? OutboxStatus.permanentFailure
                  : OutboxStatus.failed,
              retryCount: nextRetry,
              lastError: isPermanent
                  ? 'Max retries (5) exceeded: $e'
                  : e.toString(),
              lastAttemptAt: DateTime.now(),
              nextAttemptAt:
                  DateTime.now().add(Duration(seconds: backoffSeconds)),
            ));
          }
        }
      }
    } finally {
      _syncingUsers.remove(userId);
    }

    return SyncResult(synced: synced, failed: failed, skipped: skipped);
  }

  bool _isAuthError(String err) {
    return err.contains('401') ||
        err.contains('403') ||
        err.contains('unauthorized') ||
        err.contains('forbidden') ||
        err.contains('jwt') ||
        err.contains('invalid token');
  }

  bool _isAuthRecoverable(String err) {
    final sanitized = err.replaceAll('401/403', '');
    if (sanitized.contains('403') || sanitized.contains('forbidden')) return false;
    return err.contains('401') ||
        err.contains('unauthorized') ||
        err.contains('jwt') ||
        err.contains('invalid token') ||
        err.contains('token expired');
  }

  bool _isValidationError(String err) {
    return err.contains('violates') ||
        err.contains('invalid input') ||
        err.contains('bad request');
  }

  // ── Local Favorites Snapshot Caching ────────────────────────────────────────

  List<FavoriteBook> getCachedFavorites(String userId) {
    try {
      final box = _getBox();
      if (box == null) return [];
      final raw = box.get('favorites_cache_$userId');
      if (raw == null) return [];

      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) return [];

      final favs = <FavoriteBook>[];
      for (final item in decoded) {
        if (item is Map) {
          try {
            favs.add(FavoriteBookDto.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
      return favs;
    } catch (e) {
      debugPrint('Error reading favorites cache for user $userId: $e');
      return [];
    }
  }

  void saveFavoritesToCache(String userId, List<FavoriteBook> favorites) {
    try {
      final box = _getBox();
      if (box == null) return;
      final encoded = jsonEncode(favorites.map((f) => FavoriteBookDto.toJson(f)).toList());
      box.put('favorites_cache_$userId', encoded).catchError((e) {
        debugPrint('Async write error favorites_cache_$userId: $e');
      });
    } catch (e) {
      debugPrint('Error saving favorites cache for user $userId: $e');
    }
  }
}
