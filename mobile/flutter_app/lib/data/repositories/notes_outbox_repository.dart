import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../domain/entities/favorite_outbox_item.dart' show OutboxStatus;
import '../../domain/entities/learning_note.dart';
import '../../domain/entities/note_outbox_item.dart';
import '../../services/api_service.dart';
import 'favorites_outbox_repository.dart' show SyncResult;

class NotesOutboxRepository {
  final Box? _injectedOutboxBox;
  final Box? _injectedCacheBox;
  final Set<String> _syncingUsers = {};

  static const int maxItemsPerUser = 200;

  NotesOutboxRepository([this._injectedOutboxBox, this._injectedCacheBox]);

  Box? _getOutboxBox() {
    if (_injectedOutboxBox != null) return _injectedOutboxBox;
    if (Hive.isBoxOpen('notes_outbox')) {
      return Hive.box('notes_outbox');
    }
    if (Hive.isBoxOpen('favorites_outbox')) {
      return Hive.box('favorites_outbox');
    }
    if (Hive.isBoxOpen('books_cache')) {
      return Hive.box('books_cache');
    }
    return null;
  }

  Box? _getCacheBox() {
    if (_injectedCacheBox != null) return _injectedCacheBox;
    if (Hive.isBoxOpen('notes_cache')) {
      return Hive.box('notes_cache');
    }
    if (Hive.isBoxOpen('books_cache')) {
      return Hive.box('books_cache');
    }
    return _getOutboxBox();
  }

  String _buildOutboxKey(String userId, String clientNoteId) => 'outbox_note_${userId}_$clientNoteId';
  String _buildCacheKey(String userId, String noteId) => 'cache_note_${userId}_$noteId';

  // ── Cache Management ────────────────────────────────────────────────────────

  Future<void> saveCachedNote(String userId, LearningNote note) async {
    try {
      final box = _getCacheBox();
      if (box == null) return;
      final key = _buildCacheKey(userId, note.id);
      await box.put(key, jsonEncode(note.toJson()));
    } catch (e) {
      debugPrint('[NotesOutboxRepo] Error saving cached note: $e');
    }
  }

  Future<void> saveCachedNotes(String userId, List<LearningNote> notes) async {
    try {
      final box = _getCacheBox();
      if (box == null) return;
      for (final note in notes) {
        final key = _buildCacheKey(userId, note.id);
        await box.put(key, jsonEncode(note.toJson()));
      }
    } catch (e) {
      debugPrint('[NotesOutboxRepo] Error batch saving cached notes: $e');
    }
  }

  List<LearningNote> getCachedNotes(
    String userId, {
    String? bookId,
    String? noteType,
    String? query,
  }) {
    try {
      final box = _getCacheBox();
      if (box == null) return [];

      final prefix = 'cache_note_${userId}_';
      final notes = <LearningNote>[];

      for (final key in box.keys) {
        if (key.toString().startsWith(prefix)) {
          final raw = box.get(key);
          if (raw == null) continue;
          try {
            final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
            if (decoded is Map<String, dynamic>) {
              notes.add(LearningNote.fromJson(decoded));
            } else if (decoded is Map) {
              notes.add(LearningNote.fromJson(Map<String, dynamic>.from(decoded)));
            }
          } catch (e) {
            debugPrint('[NotesOutboxRepo] Corrupt note cache entry for $key: $e');
          }
        }
      }

      var filtered = notes;
      if (bookId != null && bookId.isNotEmpty) {
        filtered = filtered.where((n) => n.bookId == bookId).toList();
      }
      if (noteType != null && noteType.isNotEmpty) {
        filtered = filtered.where((n) => n.noteType == noteType).toList();
      }
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        filtered = filtered.where((n) => n.content.toLowerCase().contains(q)).toList();
      }

      // Sort descending by createdAt
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return filtered;
    } catch (e) {
      debugPrint('[NotesOutboxRepo] Error reading cached notes: $e');
      return [];
    }
  }

  Future<void> removeCachedNote(String userId, String noteId) async {
    try {
      final box = _getCacheBox();
      if (box == null) return;
      await box.delete(_buildCacheKey(userId, noteId));
    } catch (e) {
      debugPrint('[NotesOutboxRepo] Error removing cached note: $e');
    }
  }

  // ── Outbox Management ───────────────────────────────────────────────────────

  NoteOutboxItem? getItem(String userId, String clientNoteId) {
    try {
      final box = _getOutboxBox();
      if (box == null) return null;
      final raw = box.get(_buildOutboxKey(userId, clientNoteId));
      if (raw == null) return null;

      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      NoteOutboxItem? item;
      if (decoded is Map<String, dynamic>) {
        item = NoteOutboxItem.fromJson(decoded);
      } else if (decoded is Map) {
        item = NoteOutboxItem.fromJson(Map<String, dynamic>.from(decoded));
      }
      if (item != null && !_syncingUsers.contains(userId) && item.status == OutboxStatus.syncing) {
        return item.copyWith(status: OutboxStatus.pending);
      }
      return item;
    } catch (e) {
      debugPrint('[NotesOutboxRepo] Error reading item ($userId, $clientNoteId): $e');
      return null;
    }
  }

  List<NoteOutboxItem> getPendingItems(String userId) {
    try {
      final box = _getOutboxBox();
      if (box == null) return [];

      final prefix = 'outbox_note_${userId}_';
      final items = <NoteOutboxItem>[];

      for (final key in box.keys) {
        if (key.toString().startsWith(prefix)) {
          final raw = box.get(key);
          if (raw == null) continue;
          try {
            final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
            if (decoded is Map<String, dynamic>) {
              items.add(NoteOutboxItem.fromJson(decoded));
            } else if (decoded is Map) {
              items.add(NoteOutboxItem.fromJson(Map<String, dynamic>.from(decoded)));
            }
          } catch (e) {
            debugPrint('[NotesOutboxRepo] Corrupt outbox entry for key $key: $e');
          }
        }
      }

      // Recover orphaned items stuck in syncing
      if (!_syncingUsers.contains(userId)) {
        for (int i = 0; i < items.length; i++) {
          if (items[i].status == OutboxStatus.syncing) {
            final recovered = items[i].copyWith(status: OutboxStatus.pending);
            items[i] = recovered;
            box.put(_buildOutboxKey(userId, recovered.clientNoteId), jsonEncode(recovered.toJson())).catchError((e) {
              debugPrint('[NotesOutboxRepo] Error persisting recovered item: $e');
            });
          }
        }
      }

      // FIFO order
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return items;
    } catch (e) {
      debugPrint('[NotesOutboxRepo] Error loading pending items for user $userId: $e');
      return [];
    }
  }

  Future<void> removeItem(String userId, String clientNoteId) async {
    final box = _getOutboxBox();
    if (box == null) return;
    await box.delete(_buildOutboxKey(userId, clientNoteId));
  }

  Future<void> enqueueCreate({
    required String userId,
    required String clientNoteId,
    required String bookId,
    required String noteType,
    required String content,
    String? bookTitle,
    String? bookAuthor,
    String? bookThumbnail,
  }) async {
    final box = _getOutboxBox();
    if (box == null) return;

    final item = NoteOutboxItem(
      id: _buildOutboxKey(userId, clientNoteId),
      userId: userId,
      clientNoteId: clientNoteId,
      bookId: bookId,
      action: NoteOutboxAction.create,
      noteType: noteType,
      content: content,
      createdAt: DateTime.now(),
      status: OutboxStatus.pending,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookThumbnail: bookThumbnail,
    );

    await box.put(item.id, jsonEncode(item.toJson()));
  }

  Future<void> enqueueUpdate({
    required String userId,
    required String clientNoteId,
    String? serverId,
    required String bookId,
    required String content,
    String? noteType,
  }) async {
    final box = _getOutboxBox();
    if (box == null) return;

    final existing = getItem(userId, clientNoteId);
    if (existing != null && existing.action == NoteOutboxAction.create) {
      // Conflict Resolution: Updating a note that hasn't synced yet simply updates the pending create
      final updatedCreate = existing.copyWith(
        content: content,
        noteType: noteType ?? existing.noteType,
        createdAt: DateTime.now(),
      );
      await box.put(_buildOutboxKey(userId, clientNoteId), jsonEncode(updatedCreate.toJson()));
      return;
    }

    final item = NoteOutboxItem(
      id: _buildOutboxKey(userId, clientNoteId),
      userId: userId,
      clientNoteId: clientNoteId,
      serverId: serverId ?? existing?.serverId,
      bookId: bookId,
      action: NoteOutboxAction.update,
      noteType: noteType ?? existing?.noteType ?? 'personal_note',
      content: content,
      createdAt: DateTime.now(),
      status: OutboxStatus.pending,
    );

    await box.put(item.id, jsonEncode(item.toJson()));
  }

  Future<void> enqueueDelete({
    required String userId,
    required String clientNoteId,
    String? serverId,
    required String bookId,
  }) async {
    final box = _getOutboxBox();
    if (box == null) return;

    final existing = getItem(userId, clientNoteId);
    if (existing != null && existing.action == NoteOutboxAction.create && existing.serverId == null) {
      // Conflict Resolution: Deleting an offline note that was never sent to server
      // eliminates both the create action and the delete action without server calls!
      await removeItem(userId, clientNoteId);
      await removeCachedNote(userId, clientNoteId);
      return;
    }

    final item = NoteOutboxItem(
      id: _buildOutboxKey(userId, clientNoteId),
      userId: userId,
      clientNoteId: clientNoteId,
      serverId: serverId ?? existing?.serverId,
      bookId: bookId,
      action: NoteOutboxAction.delete,
      noteType: existing?.noteType ?? 'personal_note',
      content: existing?.content ?? '',
      createdAt: DateTime.now(),
      status: OutboxStatus.pending,
    );

    await box.put(item.id, jsonEncode(item.toJson()));
    await removeCachedNote(userId, clientNoteId);
    if (serverId != null) {
      await removeCachedNote(userId, serverId);
    }
  }

  void resetAuthFailures(String userId) {
    try {
      final box = _getOutboxBox();
      if (box == null) return;

      final items = getPendingItems(userId);
      for (final item in items) {
        if (item.status == OutboxStatus.failed &&
            (item.lastError?.toLowerCase().contains('401') == true ||
                item.lastError?.toLowerCase().contains('unauthorized') == true)) {
          final reset = item.copyWith(
            status: OutboxStatus.pending,
            clearLastError: true,
          );
          box.put(_buildOutboxKey(userId, reset.clientNoteId), jsonEncode(reset.toJson()));
        }
      }
    } catch (e) {
      debugPrint('[NotesOutboxRepo] Error resetting auth failures: $e');
    }
  }

  Future<SyncResult> syncUserOutbox({
    required String userId,
    required ApiService apiService,
    bool forceRetry = false,
  }) async {
    final box = _getOutboxBox();
    if (box == null) {
      return const SyncResult(synced: 0, failed: 0, skipped: 0);
    }

    if (_syncingUsers.contains(userId)) {
      debugPrint('[NotesOutboxRepo] Sync already running for user $userId. Skipping duplicate.');
      return const SyncResult(synced: 0, failed: 0, skipped: 0);
    }

    _syncingUsers.add(userId);
    int synced = 0;
    int failed = 0;
    int skipped = 0;

    try {
      final pending = getPendingItems(userId);
      if (pending.isEmpty) {
        return const SyncResult(synced: 0, failed: 0, skipped: 0);
      }

      for (final item in pending) {
        // Skip permanent failures unless forceRetry
        if (item.status == OutboxStatus.permanentFailure && !forceRetry) {
          skipped++;
          continue;
        }

        // Auth failure check
        if (item.status == OutboxStatus.failed &&
            (item.lastError?.toLowerCase().contains('401') == true ||
                item.lastError?.toLowerCase().contains('unauthorized') == true) &&
            !forceRetry) {
          skipped++;
          continue;
        }

        // Mark syncing
        final inFlight = item.copyWith(
          status: OutboxStatus.syncing,
          lastAttemptAt: DateTime.now(),
        );
        await box.put(_buildOutboxKey(userId, item.clientNoteId), jsonEncode(inFlight.toJson()));

        try {
          if (item.action == NoteOutboxAction.create) {
            final created = await apiService.createNote(
              bookId: item.bookId,
              noteType: item.noteType,
              content: item.content,
              clientId: item.clientNoteId,
            );

            if (created != null) {
              // Successfully synced to server!
              // Update cache with server UUID and clear pending flag
              await removeCachedNote(userId, item.clientNoteId);
              await saveCachedNote(
                userId,
                created.copyWith(
                  isPendingSync: false,
                  isSyncFailed: false,
                  clientId: item.clientNoteId,
                ),
              );
              await removeItem(userId, item.clientNoteId);
              synced++;
            } else {
              throw Exception('Server returned null on note creation');
            }
          } else if (item.action == NoteOutboxAction.update) {
            final targetId = item.serverId ?? item.clientNoteId;
            final updated = await apiService.updateNote(
              noteId: targetId,
              content: item.content,
              noteType: item.noteType,
            );

            if (updated != null) {
              await saveCachedNote(
                userId,
                updated.copyWith(
                  isPendingSync: false,
                  isSyncFailed: false,
                  clientId: item.clientNoteId,
                ),
              );
              await removeItem(userId, item.clientNoteId);
              synced++;
            } else {
              throw Exception('Server returned null on note update');
            }
          } else if (item.action == NoteOutboxAction.delete) {
            if (item.serverId == null) {
              // Pure offline note, already deleted from cache
              await removeItem(userId, item.clientNoteId);
              synced++;
            } else {
              final ok = await apiService.deleteNote(noteId: item.serverId!);
              if (ok) {
                await removeItem(userId, item.clientNoteId);
                await removeCachedNote(userId, item.serverId!);
                synced++;
              } else {
                throw Exception('Server returned false on note delete');
              }
            }
          }
        } catch (e) {
          failed++;
          String errStr = e.toString();
          OutboxStatus nextStatus = OutboxStatus.failed;

          if (e is DioException) {
            final statusCode = e.response?.statusCode;
            if (statusCode == 401 || statusCode == 403) {
              nextStatus = OutboxStatus.failed;
              errStr = 'Authentication required ($statusCode)';
            } else if (statusCode == 400 || statusCode == 422) {
              nextStatus = OutboxStatus.permanentFailure;
              errStr = 'Validation client error ($statusCode)';
            } else {
              errStr = 'Network or server error ($statusCode)';
            }
          }

          final failedItem = item.copyWith(
            status: nextStatus,
            retryCount: item.retryCount + 1,
            lastError: errStr,
            lastAttemptAt: DateTime.now(),
          );
          await box.put(_buildOutboxKey(userId, item.clientNoteId), jsonEncode(failedItem.toJson()));

          // Mark cache note as sync failed
          final cached = getCachedNotes(userId).where((n) => n.id == item.clientNoteId || n.id == item.serverId).firstOrNull;
          if (cached != null) {
            await saveCachedNote(
              userId,
              cached.copyWith(isSyncFailed: true, syncError: errStr),
            );
          }
        }
      }

      return SyncResult(synced: synced, failed: failed, skipped: skipped);
    } finally {
      _syncingUsers.remove(userId);
    }
  }
}

