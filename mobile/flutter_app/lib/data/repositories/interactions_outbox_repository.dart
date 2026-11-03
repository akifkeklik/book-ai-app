import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../domain/entities/favorite_outbox_item.dart' show OutboxStatus;
import '../../domain/entities/interaction_outbox_item.dart';
import '../../services/api_service.dart';
import 'favorites_outbox_repository.dart' show SyncResult;

class InteractionsOutboxRepository {
  final Box? _injectedBox;
  final Set<String> _syncingUsers = {};

  static const int maxItemsPerUser = 100;
  static const int maxRetentionDays = 30;

  InteractionsOutboxRepository([this._injectedBox]);

  Box? _getBox() {
    if (_injectedBox != null) return _injectedBox;
    if (Hive.isBoxOpen('interactions_outbox')) {
      return Hive.box('interactions_outbox');
    }
    if (Hive.isBoxOpen('favorites_outbox')) {
      return Hive.box('favorites_outbox');
    }
    if (Hive.isBoxOpen('books_cache')) {
      return Hive.box('books_cache');
    }
    return null;
  }

  String _buildKey(String userId, String isbn13) => 'outbox_interaction_${userId}_$isbn13';

  // ── Outbox Item Management ──────────────────────────────────────────────────

  InteractionOutboxItem? getItem(String userId, String isbn13) {
    try {
      final box = _getBox();
      if (box == null) return null;
      final raw = box.get(_buildKey(userId, isbn13));
      if (raw == null) return null;

      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      InteractionOutboxItem? item;
      if (decoded is Map<String, dynamic>) {
        item = InteractionOutboxItem.fromJson(decoded);
      } else if (decoded is Map) {
        item = InteractionOutboxItem.fromJson(Map<String, dynamic>.from(decoded));
      }
      if (item != null && !_syncingUsers.contains(userId) && item.status == OutboxStatus.syncing) {
        return item.copyWith(status: OutboxStatus.pending);
      }
      return item;
    } catch (e) {
      debugPrint('Error reading interaction outbox item ($userId, $isbn13): $e');
      return null;
    }
  }

  bool hasPendingItem(String userId, String isbn13) {
    return getItem(userId, isbn13) != null;
  }

  List<InteractionOutboxItem> getPendingItems(String userId) {
    try {
      final box = _getBox();
      if (box == null) return [];

      final prefix = 'outbox_interaction_${userId}_';
      final items = <InteractionOutboxItem>[];

      for (final key in box.keys) {
        if (key.toString().startsWith(prefix)) {
          final raw = box.get(key);
          if (raw == null) continue;
          try {
            final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
            if (decoded is Map<String, dynamic>) {
              items.add(InteractionOutboxItem.fromJson(decoded));
            } else if (decoded is Map) {
              items.add(InteractionOutboxItem.fromJson(Map<String, dynamic>.from(decoded)));
            }
          } catch (e) {
            debugPrint('Corrupt interaction outbox entry for key $key: $e');
          }
        }
      }

      // Recover orphaned items stuck in syncing after process termination
      if (!_syncingUsers.contains(userId)) {
        for (int i = 0; i < items.length; i++) {
          if (items[i].status == OutboxStatus.syncing) {
            final recovered = items[i].copyWith(status: OutboxStatus.pending);
            items[i] = recovered;
            box.put(_buildKey(userId, recovered.isbn13), jsonEncode(recovered.toJson())).catchError((e) {
              debugPrint('Error persisting recovered interaction outbox item: $e');
            });
          }
        }
      }

      // FIFO order
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return items;
    } catch (e) {
      debugPrint('Error loading pending interactions for user $userId: $e');
      return [];
    }
  }

  Future<void> enqueue({
    required String userId,
    required String isbn13,
    required String interaction,
  }) async {
    final box = _getBox();
    if (box == null) return;

    _pruneOldItems(userId, box);

    final existing = getItem(userId, isbn13);
    final key = _buildKey(userId, isbn13);

    // Desired-state idempotency: update to latest intended interaction
    final item = InteractionOutboxItem(
      id: 'interaction_${userId}_$isbn13',
      userId: userId,
      isbn13: isbn13,
      interaction: interaction,
      createdAt: existing?.createdAt ?? DateTime.now(),
      retryCount: 0,
      status: OutboxStatus.pending,
      lastError: null,
      lastAttemptAt: null,
      nextAttemptAt: null,
    );

    try {
      await box.put(key, jsonEncode(item.toJson()));
    } catch (e) {
      debugPrint('Error saving interaction outbox item $key: $e');
      rethrow;
    }
  }

  Future<void> removeItem(String userId, String isbn13) async {
    try {
      final box = _getBox();
      if (box == null) return;
      await box.delete(_buildKey(userId, isbn13));
    } catch (e) {
      debugPrint('Error removing interaction outbox item ($userId, $isbn13): $e');
    }
  }

  Future<void> updateItem(InteractionOutboxItem item) async {
    try {
      final box = _getBox();
      if (box == null) return;
      await box.put(_buildKey(item.userId, item.isbn13), jsonEncode(item.toJson()));
    } catch (e) {
      debugPrint('Error updating interaction outbox item ${item.id}: $e');
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

  Future<void> resetAuthFailures(String userId) async {
    try {
      final box = _getBox();
      if (box == null) return;
      final items = getPendingItems(userId);
      for (final item in items) {
        if (item.status == OutboxStatus.permanentFailure &&
            _isAuthRecoverable(item.lastError ?? '')) {
          final reset = item.copyWith(
            status: OutboxStatus.pending,
            retryCount: 0,
            clearLastError: true,
            clearNextAttemptAt: true,
          );
          await box.put(_buildKey(userId, reset.isbn13), jsonEncode(reset.toJson()));
        }
      }
    } catch (e) {
      debugPrint('Error resetting interaction auth failures for user $userId: $e');
    }
  }

  void _pruneOldItems(String userId, Box box) {
    try {
      final items = getPendingItems(userId);
      final now = DateTime.now();

      for (final item in items) {
        if (item.status == OutboxStatus.permanentFailure &&
            now.difference(item.createdAt).inDays > maxRetentionDays) {
          box.delete(_buildKey(item.userId, item.isbn13));
        }
      }

      if (items.length >= maxItemsPerUser) {
        final toEvictCount = items.length - maxItemsPerUser + 1;
        final candidates = List<InteractionOutboxItem>.from(items);
        candidates.sort((a, b) {
          int rank(InteractionOutboxItem item) {
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
    required ApiService apiService,
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
        if (item.status == OutboxStatus.permanentFailure && !forceRetry) {
          skipped++;
          continue;
        }

        if (item.retryCount >= 5 && !forceRetry) {
          await updateItem(item.copyWith(
            status: OutboxStatus.permanentFailure,
            lastError: 'Max retries (5) exceeded.',
          ));
          skipped++;
          continue;
        }

        if (!forceRetry &&
            item.status == OutboxStatus.failed &&
            item.nextAttemptAt != null &&
            DateTime.now().isBefore(item.nextAttemptAt!)) {
          skipped++;
          continue;
        }

        await updateItem(item.copyWith(status: OutboxStatus.syncing));

        try {
          final success = await apiService.submitFeedback(
            userId: item.userId,
            bookId: item.isbn13,
            interaction: item.interaction,
          );

          if (success) {
            await removeItem(item.userId, item.isbn13);
            synced++;
          } else {
            throw Exception('Backend returned failure status');
          }
        } catch (e) {
          failed++;
          final isAuth = _isAuthError(e);
          final is4xx = _is4xxClientError(e);

          if (isAuth) {
            final statusCode = e is DioException ? e.response?.statusCode : null;
            final prefix = statusCode != null ? 'HTTP $statusCode: ' : '';
            await updateItem(item.copyWith(
              status: OutboxStatus.permanentFailure,
              lastError: '$prefix$e',
              lastAttemptAt: DateTime.now(),
            ));
            break; // Pause queue for this user until re-login
          } else if (is4xx) {
            final statusCode = e is DioException ? e.response?.statusCode : null;
            final prefix = statusCode != null ? 'HTTP $statusCode: ' : '';
            await updateItem(item.copyWith(
              status: OutboxStatus.permanentFailure,
              lastError: '$prefix$e',
              lastAttemptAt: DateTime.now(),
            ));
          } else {
            int? retryAfterSeconds;
            if (e is DioException && e.response?.statusCode == 429) {
              final headerVal = e.response?.headers.value('retry-after');
              if (headerVal != null) {
                retryAfterSeconds = int.tryParse(headerVal.trim());
              }
            }
            final nextRetry = item.retryCount + 1;
            if (nextRetry >= 5) {
              await updateItem(item.copyWith(
                status: OutboxStatus.permanentFailure,
                retryCount: nextRetry,
                lastError: 'Max retries (5) exceeded. Last error: $e',
                lastAttemptAt: DateTime.now(),
              ));
            } else {
              final backoffSeconds = retryAfterSeconds != null
                  ? retryAfterSeconds.clamp(1, 300)
                  : (1 << nextRetry).clamp(2, 300);
              await updateItem(item.copyWith(
                status: OutboxStatus.failed,
                retryCount: nextRetry,
                lastError: e.toString(),
                lastAttemptAt: DateTime.now(),
                nextAttemptAt: DateTime.now().add(Duration(seconds: backoffSeconds)),
              ));
            }
          }
        }
      }

      return SyncResult(synced: synced, failed: failed, skipped: skipped);
    } finally {
      _syncingUsers.remove(userId);
    }
  }

  bool _isAuthError(dynamic error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 401 || code == 403) return true;
    }
    final errStr = error.toString().toLowerCase();
    return errStr.contains('401') ||
        errStr.contains('403') ||
        errStr.contains('unauthorized') ||
        errStr.contains('jwt') ||
        errStr.contains('token') ||
        errStr.contains('session expired');
  }

  bool _isAuthRecoverable(dynamic error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 401) return true;
      if (code == 403) return false;
    }
    final errStr = error.toString().toLowerCase();
    final sanitized = errStr.replaceAll('401/403', '');
    if (sanitized.contains('403') || sanitized.contains('forbidden')) return false;
    return errStr.contains('401') ||
        errStr.contains('unauthorized') ||
        errStr.contains('jwt') ||
        errStr.contains('token') ||
        errStr.contains('session expired');
  }

  bool _is4xxClientError(dynamic error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 400 || code == 422) return true;
    }
    final errStr = error.toString().toLowerCase();
    return errStr.contains('400') ||
        errStr.contains('422') ||
        errStr.contains('bad request') ||
        errStr.contains('validation');
  }
}
