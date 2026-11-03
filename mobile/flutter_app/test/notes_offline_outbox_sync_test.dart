import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:book_ai_app/domain/entities/favorite_outbox_item.dart' show OutboxStatus;
import 'package:book_ai_app/domain/entities/learning_note.dart';
import 'package:book_ai_app/domain/entities/note_outbox_item.dart';
import 'package:book_ai_app/data/repositories/notes_outbox_repository.dart';
import 'package:book_ai_app/providers/notes_provider.dart';
import 'package:book_ai_app/services/api_service.dart';

class FakeBox implements Box {
  final Map<dynamic, dynamic> _store = {};

  @override
  Iterable<dynamic> get keys => _store.keys.toList();

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => _store[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _store.remove(key);
  }

  @override
  bool containsKey(dynamic key) => _store.containsKey(key);

  @override
  Future<int> clear() async {
    final count = _store.length;
    _store.clear();
    return count;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestApiService implements ApiService {
  final List<LearningNote> serverDb = [];
  bool shouldThrowNetworkError = false;
  bool shouldThrowAuthError = false;
  bool shouldThrowClientError = false;

  @override
  Future<LearningNote?> createNote({
    required String bookId,
    required String noteType,
    required String content,
    String? clientId,
  }) async {
    if (shouldThrowNetworkError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/notes'),
        type: DioExceptionType.connectionTimeout,
        error: 'Network connection timed out',
      );
    }
    if (shouldThrowAuthError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/notes'),
        response: Response(requestOptions: RequestOptions(path: '/api/notes'), statusCode: 401),
        type: DioExceptionType.badResponse,
      );
    }
    if (shouldThrowClientError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/notes'),
        response: Response(requestOptions: RequestOptions(path: '/api/notes'), statusCode: 422),
        type: DioExceptionType.badResponse,
      );
    }

    // Idempotency check: if note with same clientId exists, return it!
    if (clientId != null && clientId.isNotEmpty) {
      final existing = serverDb.where((n) => n.clientId == clientId).firstOrNull;
      if (existing != null) return existing;
    }

    final note = LearningNote(
      id: 'server-uuid-${serverDb.length + 1}',
      userId: 'test_user_1',
      bookId: bookId,
      noteType: noteType,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      clientId: clientId,
    );
    serverDb.insert(0, note);
    return note;
  }

  @override
  Future<LearningNote?> updateNote({
    required String noteId,
    required String content,
    String? noteType,
  }) async {
    if (shouldThrowNetworkError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/notes'),
        type: DioExceptionType.connectionTimeout,
      );
    }
    final index = serverDb.indexWhere((n) => n.id == noteId || n.clientId == noteId);
    if (index == -1) return null;
    final existing = serverDb[index];
    final updated = existing.copyWith(
      content: content,
      noteType: noteType ?? existing.noteType,
      updatedAt: DateTime.now(),
    );
    serverDb[index] = updated;
    return updated;
  }

  @override
  Future<bool> deleteNote({required String noteId}) async {
    if (shouldThrowNetworkError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/notes'),
        type: DioExceptionType.connectionTimeout,
      );
    }
    final index = serverDb.indexWhere((n) => n.id == noteId);
    if (index == -1) return false;
    serverDb.removeAt(index);
    return true;
  }

  @override
  Future<List<LearningNote>> getNotes({
    String? bookId,
    String? noteType,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    if (shouldThrowNetworkError) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/notes'),
        type: DioExceptionType.connectionTimeout,
      );
    }
    var list = List<LearningNote>.from(serverDb);
    if (bookId != null && bookId.isNotEmpty) {
      list = list.where((n) => n.bookId == bookId).toList();
    }
    if (noteType != null && noteType.isNotEmpty) {
      list = list.where((n) => n.noteType == noteType).toList();
    }
    return list;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FAZ 1 — Mobile Offline-First Learning Notes & Outbox Sync Tests', () {
    late FakeBox outboxBox;
    late FakeBox cacheBox;
    late NotesOutboxRepository repository;
    late FakeTestApiService fakeApi;

    setUp(() {
      outboxBox = FakeBox();
      cacheBox = FakeBox();
      repository = NotesOutboxRepository(outboxBox, cacheBox);
      fakeApi = FakeTestApiService();
    });

    test('1. Offline note creation: stored locally, queue populated, survives simulated restart', () async {
      const userId = 'user-alice';
      const clientId = 'client-uuid-1';

      // User creates note offline
      await repository.enqueueCreate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        noteType: 'key_takeaway',
        content: 'Small habits compound dramatically over time.',
        bookTitle: 'Atomic Habits',
      );
      await repository.saveCachedNote(
        userId,
        LearningNote(
          id: clientId,
          userId: userId,
          bookId: '9780735211292',
          noteType: 'key_takeaway',
          content: 'Small habits compound dramatically over time.',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isPendingSync: true,
          clientId: clientId,
          bookTitle: 'Atomic Habits',
        ),
      );

      // Verify pending outbox item
      final pending = repository.getPendingItems(userId);
      expect(pending.length, 1);
      expect(pending.first.clientNoteId, clientId);
      expect(pending.first.action, NoteOutboxAction.create);
      expect(pending.first.status, OutboxStatus.pending);

      // Verify cached note
      final cached = repository.getCachedNotes(userId);
      expect(cached.length, 1);
      expect(cached.first.isPendingSync, isTrue);
      expect(cached.first.content, 'Small habits compound dramatically over time.');

      // Simulate App Restart with new repository pointing to same underlying boxes
      final restartedRepo = NotesOutboxRepository(outboxBox, cacheBox);
      final restartedPending = restartedRepo.getPendingItems(userId);
      expect(restartedPending.length, 1);
      expect(restartedPending.first.clientNoteId, clientId);

      final restartedCached = restartedRepo.getCachedNotes(userId);
      expect(restartedCached.length, 1);
      expect(restartedCached.first.content, 'Small habits compound dramatically over time.');
    });

    test('2. Sync when online: maps client ID to server UUID and cleans queue', () async {
      const userId = 'user-alice';
      const clientId = 'client-uuid-2';

      await repository.enqueueCreate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        noteType: 'personal_note',
        content: 'Apply habit stacking today.',
      );

      // Perform sync
      final result = await repository.syncUserOutbox(
        userId: userId,
        apiService: fakeApi,
      );

      expect(result.synced, 1);
      expect(result.failed, 0);

      // Outbox queue must be empty
      expect(repository.getPendingItems(userId), isEmpty);

      // Server DB has the record
      expect(fakeApi.serverDb.length, 1);
      expect(fakeApi.serverDb.first.clientId, clientId);
      expect(fakeApi.serverDb.first.id, startsWith('server-uuid-'));

      // Local cache updated with server UUID and cleared pending flag
      final cached = repository.getCachedNotes(userId);
      expect(cached.length, 1);
      expect(cached.first.isPendingSync, isFalse);
      expect(cached.first.id, startsWith('server-uuid-'));
    });

    test('3. Idempotency: retry does not produce duplicate server records', () async {
      const userId = 'user-alice';
      const clientId = 'client-uuid-3';

      // First sync
      await repository.enqueueCreate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        noteType: 'question',
        content: 'How long until a habit is automatic?',
      );
      final r1 = await repository.syncUserOutbox(userId: userId, apiService: fakeApi);
      expect(r1.synced, 1);
      expect(fakeApi.serverDb.length, 1);
      final originalServerId = fakeApi.serverDb.first.id;

      // Second sync simulated with same clientId (e.g. timeout retry)
      await repository.enqueueCreate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        noteType: 'question',
        content: 'How long until a habit is automatic?',
      );
      final r2 = await repository.syncUserOutbox(userId: userId, apiService: fakeApi);
      expect(r2.synced, 1);

      // Still exactly 1 record on server
      expect(fakeApi.serverDb.length, 1);
      expect(fakeApi.serverDb.first.id, originalServerId);
    });

    test('4. Conflict policy: editing un-synced offline note updates create item in-place', () async {
      const userId = 'user-alice';
      const clientId = 'client-uuid-4';

      await repository.enqueueCreate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        noteType: 'personal_note',
        content: 'Draft initial thought',
      );

      // Edit while still offline
      await repository.enqueueUpdate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        content: 'Polished finalized thought',
      );

      // Queue depth remains 1 (updated in place)
      final pending = repository.getPendingItems(userId);
      expect(pending.length, 1);
      expect(pending.first.action, NoteOutboxAction.create);
      expect(pending.first.content, 'Polished finalized thought');

      // Sync delivers the finalized content directly
      await repository.syncUserOutbox(userId: userId, apiService: fakeApi);
      expect(fakeApi.serverDb.length, 1);
      expect(fakeApi.serverDb.first.content, 'Polished finalized thought');
    });

    test('5. Conflict policy: deleting un-synced offline note cancels out without network request', () async {
      const userId = 'user-alice';
      const clientId = 'client-uuid-5';

      await repository.enqueueCreate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        noteType: 'personal_note',
        content: 'Accidental note',
      );

      // Delete while still offline
      await repository.enqueueDelete(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
      );

      // Both outbox item and cache entry are purged immediately
      expect(repository.getPendingItems(userId), isEmpty);
      expect(repository.getCachedNotes(userId), isEmpty);

      // Sync does nothing and 0 calls sent to server
      final res = await repository.syncUserOutbox(userId: userId, apiService: fakeApi);
      expect(res.synced, 0);
      expect(fakeApi.serverDb, isEmpty);
    });

    test('6. Network outage & recovery: retains item in outbox, increments retry count, recovers when online', () async {
      const userId = 'user-alice';
      const clientId = 'client-uuid-6';

      await repository.enqueueCreate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        noteType: 'key_takeaway',
        content: 'Identity-based habits.',
      );

      // Simulate network down
      fakeApi.shouldThrowNetworkError = true;
      final r1 = await repository.syncUserOutbox(userId: userId, apiService: fakeApi);
      expect(r1.failed, 1);
      expect(r1.synced, 0);

      // Note is NOT lost! Still in queue with incremented retry count
      final pending = repository.getPendingItems(userId);
      expect(pending.length, 1);
      expect(pending.first.retryCount, 1);
      expect(pending.first.status, OutboxStatus.failed);

      // Network restored
      fakeApi.shouldThrowNetworkError = false;
      final r2 = await repository.syncUserOutbox(userId: userId, apiService: fakeApi, forceRetry: true);
      expect(r2.synced, 1);
      expect(r2.failed, 0);
      expect(repository.getPendingItems(userId), isEmpty);
    });

    test('7. Auth error (401): keeps note in outbox, resetAuthFailures resumes upon re-auth', () async {
      const userId = 'user-alice';
      const clientId = 'client-uuid-7';

      await repository.enqueueCreate(
        userId: userId,
        clientNoteId: clientId,
        bookId: '9780735211292',
        noteType: 'personal_note',
        content: 'Important private insight',
      );

      // Auth expired (401)
      fakeApi.shouldThrowAuthError = true;
      final r1 = await repository.syncUserOutbox(userId: userId, apiService: fakeApi);
      expect(r1.failed, 1);

      // Note NOT deleted
      final item = repository.getItem(userId, clientId);
      expect(item, isNotNull);
      expect(item!.status, OutboxStatus.failed);
      expect(item.lastError, contains('401'));

      // Auth recovery triggered on token refresh
      repository.resetAuthFailures(userId);
      final resetItem = repository.getItem(userId, clientId);
      expect(resetItem!.status, OutboxStatus.pending);

      // Sync succeeds after auth restored
      fakeApi.shouldThrowAuthError = false;
      final r2 = await repository.syncUserOutbox(userId: userId, apiService: fakeApi);
      expect(r2.synced, 1);
    });

    test('8. Strict Account Isolation: User A outbox is never dispatched for User B', () async {
      const userA = 'user-alice';
      const userB = 'user-bob';

      // User A queues note
      await repository.enqueueCreate(
        userId: userA,
        clientNoteId: 'client-alice-note',
        bookId: '9780735211292',
        noteType: 'personal_note',
        content: 'Alice private note',
      );

      // Sync User B's outbox
      final resB = await repository.syncUserOutbox(userId: userB, apiService: fakeApi);
      expect(resB.synced, 0);
      expect(resB.failed, 0);

      // Server DB remains empty (Alice's note was NOT sent!)
      expect(fakeApi.serverDb, isEmpty);

      // Alice's note remains pending in her own queue
      expect(repository.getPendingItems(userA).length, 1);
      expect(repository.getPendingItems(userB), isEmpty);
    });

    test('9. NotesProvider offline-first flow: immediately visible, marked pending sync', () async {
      final provider = NotesProvider(
        apiService: fakeApi,
        outboxRepository: repository,
      );
      provider.setActiveUser('user-charlie');

      // Even if network fails, addNote returns true
      fakeApi.shouldThrowNetworkError = true;

      final success = await provider.addNote(
        bookId: '9780143127741',
        noteType: 'key_takeaway',
        content: 'Offline note created on plane.',
        userId: 'user-charlie',
        bookTitle: 'İnce Memed',
      );

      expect(success, isTrue);
      final notes = provider.getBookNotes('9780143127741');
      expect(notes.length, 1);
      expect(notes.first.content, 'Offline note created on plane.');
      expect(notes.first.isPendingSync, isTrue);

      // Note is safely persisted in Hive cache & outbox
      final cached = repository.getCachedNotes('user-charlie');
      expect(cached.length, 1);
      expect(repository.getPendingItems('user-charlie').length, 1);
    });
  });
}
