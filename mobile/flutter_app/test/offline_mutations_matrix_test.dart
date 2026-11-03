import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:book_ai_app/domain/entities/favorite_outbox_item.dart';
import 'package:book_ai_app/domain/entities/interaction_outbox_item.dart';
import 'package:book_ai_app/data/repositories/favorites_outbox_repository.dart';
import 'package:book_ai_app/data/repositories/interactions_outbox_repository.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:book_ai_app/services/supabase_service.dart';

// ---------------------------------------------------------------------------
// In-Memory Test Box Double (Simulates Persistent Hive Box on Disk)
// ---------------------------------------------------------------------------

class MatrixFakeBox implements Box {
  final Map<dynamic, dynamic> _store = {};
  bool throwOnRead = false;
  bool throwOnWrite = false;

  @override
  Iterable<dynamic> get keys => _store.keys.toList();

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    if (throwOnRead) throw Exception('Disk read I/O error');
    return _store[key] ?? defaultValue;
  }

  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (throwOnWrite) throw Exception('Disk write full error');
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

// ---------------------------------------------------------------------------
// Fake ApiService Test Double
// ---------------------------------------------------------------------------

class FakeMatrixApiService implements ApiService {
  final List<Map<String, String>> feedbackCalls = [];
  Exception? feedbackError;
  bool returnSuccess = true;
  int callCount = 0;

  @override
  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    callCount++;
    if (feedbackError != null) throw feedbackError!;
    feedbackCalls.add({
      'userId': userId,
      'bookId': bookId,
      'interaction': interaction,
    });
    return returnSuccess;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Fake SupabaseService Test Double
// ---------------------------------------------------------------------------

class FakeMatrixSupabaseService implements SupabaseService {
  final List<Map<String, String>> addFavoriteCalls = [];
  final List<Map<String, String>> removeFavoriteCalls = [];
  Exception? error;

  @override
  Future<void> addFavorite({
    required String userId,
    required String bookId,
    required String title,
    required String author,
    required String? imageUrl,
  }) async {
    if (error != null) throw error!;
    addFavoriteCalls.add({
      'userId': userId,
      'bookId': bookId,
      'title': title,
      'author': author,
    });
  }

  @override
  Future<void> removeFavorite(String userId, String bookId) async {
    if (error != null) throw error!;
    removeFavoriteCalls.add({
      'userId': userId,
      'bookId': bookId,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// TEST MATRIX: 10 Core Offline Resilience Scenarios
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Workstream B: Persistent Offline Outbox 10-Scenario Matrix', () {
    late MatrixFakeBox sharedBox;
    late FavoritesOutboxRepository favRepo;
    late InteractionsOutboxRepository interactionRepo;
    late FakeMatrixApiService apiService;
    late FakeMatrixSupabaseService supabaseService;

    setUp(() {
      sharedBox = MatrixFakeBox();
      favRepo = FavoritesOutboxRepository(sharedBox);
      interactionRepo = InteractionsOutboxRepository(sharedBox);
      apiService = FakeMatrixApiService();
      supabaseService = FakeMatrixSupabaseService();
    });

    // 1. Queueing a mutation offline
    test('Scenario 1: Queueing a mutation offline persists item with pending status', () async {
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'reading',
      );

      final item = interactionRepo.getItem('user_alpha', '9780452284234');
      expect(item, isNotNull);
      expect(item!.userId, 'user_alpha');
      expect(item.isbn13, '9780452284234');
      expect(item.interaction, 'reading');
      expect(item.status, OutboxStatus.pending);
      expect(item.retryCount, 0);
    });

    // 2. Persistence across process or provider recreation
    test('Scenario 2: Persistence across process/provider recreation restores outbox from storage', () async {
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'finished',
      );

      // Recreate repository pointing to the same disk/storage box
      final recreatedRepo = InteractionsOutboxRepository(sharedBox);
      final restoredItem = recreatedRepo.getItem('user_alpha', '9780452284234');

      expect(restoredItem, isNotNull);
      expect(restoredItem!.interaction, 'finished');
      expect(restoredItem.status, OutboxStatus.pending);
    });

    // 3. Successful synchronization
    test('Scenario 3: Successful synchronization drains the queue and forwards desired state', () async {
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'reading',
      );

      final result = await interactionRepo.syncUserOutbox(
        userId: 'user_alpha',
        apiService: apiService,
      );

      expect(result.synced, 1);
      expect(result.failed, 0);
      expect(apiService.feedbackCalls.length, 1);
      expect(apiService.feedbackCalls.first['interaction'], 'reading');
      expect(interactionRepo.hasPendingItem('user_alpha', '9780452284234'), isFalse);
    });

    // 4. Duplicate retry without duplicate state changes (Desired state idempotency)
    test('Scenario 4: Duplicate retry preserves idempotent desired state without toggling', () async {
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'want_to_read',
      );

      // Enqueueing the same or updated desired state does not duplicate or toggle
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'want_to_read',
      );

      final pending = interactionRepo.getPendingItems('user_alpha');
      expect(pending.length, 1);
      expect(pending.first.interaction, 'want_to_read');

      // Sync twice
      await interactionRepo.syncUserOutbox(userId: 'user_alpha', apiService: apiService);
      expect(apiService.feedbackCalls.length, 1);

      // Subsequent sync does nothing because queue was safely drained
      final secondSync = await interactionRepo.syncUserOutbox(userId: 'user_alpha', apiService: apiService);
      expect(secondSync.synced, 0);
      expect(apiService.feedbackCalls.length, 1);
    });

    // 5. Temporary network failure and retry with bounded exponential backoff
    test('Scenario 5: Temporary network failure increments retry count and sets backoff window', () async {
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'reading',
      );

      apiService.feedbackError = Exception('SocketException: Connection refused (offline)');

      final result = await interactionRepo.syncUserOutbox(
        userId: 'user_alpha',
        apiService: apiService,
      );

      expect(result.failed, 1);
      final failedItem = interactionRepo.getItem('user_alpha', '9780452284234');
      expect(failedItem, isNotNull);
      expect(failedItem!.status, OutboxStatus.failed);
      expect(failedItem.retryCount, 1);
      expect(failedItem.nextAttemptAt, isNotNull);
      expect(failedItem.nextAttemptAt!.isAfter(DateTime.now()), isTrue);

      // Second immediate attempt without forceRetry skips due to backoff
      final skippedSync = await interactionRepo.syncUserOutbox(
        userId: 'user_alpha',
        apiService: apiService,
      );
      expect(skippedSync.skipped, 1);
    });

    // 6. Permanent 4xx failure handling
    test('Scenario 6: Permanent 4xx validation/client error terminates retries with permanentFailure', () async {
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'invalid_status',
      );

      apiService.feedbackError = Exception('400 Bad Request: Invalid interaction type');

      final result = await interactionRepo.syncUserOutbox(
        userId: 'user_alpha',
        apiService: apiService,
      );

      expect(result.failed, 1);
      final item = interactionRepo.getItem('user_alpha', '9780452284234');
      expect(item, isNotNull);
      expect(item!.status, OutboxStatus.permanentFailure);
      expect(item.lastError, contains('400 Bad Request'));

      // Future syncs skip permanent failure without endless retries
      final nextSync = await interactionRepo.syncUserOutbox(
        userId: 'user_alpha',
        apiService: apiService,
      );
      expect(nextSync.skipped, 1);
      expect(nextSync.failed, 0);
    });

    // 7. Expired authentication
    test('Scenario 7: Expired authentication (401/403) halts queue for user until re-login', () async {
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'reading',
      );

      apiService.feedbackError = Exception('401 Unauthorized: JWT token expired');

      final result = await interactionRepo.syncUserOutbox(
        userId: 'user_alpha',
        apiService: apiService,
      );

      expect(result.failed, 1);
      final item = interactionRepo.getItem('user_alpha', '9780452284234');
      expect(item!.status, OutboxStatus.permanentFailure);

      // On re-authentication, resetAuthFailures restores item to pending
      interactionRepo.resetAuthFailures('user_alpha');
      final restored = interactionRepo.getItem('user_alpha', '9780452284234');
      expect(restored!.status, OutboxStatus.pending);
      expect(restored.retryCount, 0);

      // Now sync succeeds
      apiService.feedbackError = null;
      final reSync = await interactionRepo.syncUserOutbox(
        userId: 'user_alpha',
        apiService: apiService,
      );
      expect(reSync.synced, 1);
    });

    // 8. User switching and queue isolation
    test('Scenario 8: User switching preserves queue isolation (User A never synced or cleared by User B)', () async {
      await interactionRepo.enqueue(
        userId: 'user_A',
        isbn13: '9780000000001',
        interaction: 'reading',
      );
      await interactionRepo.enqueue(
        userId: 'user_B',
        isbn13: '9780000000002',
        interaction: 'finished',
      );

      // Sync for user_B
      final resultB = await interactionRepo.syncUserOutbox(
        userId: 'user_B',
        apiService: apiService,
      );

      expect(resultB.synced, 1);
      expect(apiService.feedbackCalls.length, 1);
      expect(apiService.feedbackCalls.first['userId'], 'user_B');

      // User A's item is untouched and still pending
      expect(interactionRepo.hasPendingItem('user_A', '9780000000001'), isTrue);
      expect(interactionRepo.hasPendingItem('user_B', '9780000000002'), isFalse);
    });

    // 9. Reading-status clearing without deleting favorites
    test('Scenario 9: Reading-status clearing submits "clear" without modifying favorites table', () async {
      // 1. User has favorite in favorite outbox
      await favRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        action: OutboxAction.add,
        bookTitle: '1984',
        bookAuthor: 'George Orwell',
        bookImageUrl: null,
      );

      // 2. User clears reading status offline
      await interactionRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'clear',
      );

      // Sync interaction outbox
      await interactionRepo.syncUserOutbox(
        userId: 'user_alpha',
        apiService: apiService,
      );

      expect(apiService.feedbackCalls.length, 1);
      expect(apiService.feedbackCalls.first['interaction'], 'clear');
      expect(apiService.feedbackCalls.first['bookId'], '9780452284234');

      // Sync favorites outbox
      await favRepo.syncUserOutbox(
        userId: 'user_alpha',
        supabaseService: supabaseService,
      );

      expect(supabaseService.addFavoriteCalls.length, 1);
      expect(supabaseService.removeFavoriteCalls.length, 0); // Favorite was NOT removed!
    });

    // 10. Restart recovery with pending operations
    test('Scenario 10: Restart recovery resets stuck "syncing" items back to "pending"', () async {
      // Put an item directly into the store in syncing state (simulating crash mid-sync)
      final stuckItem = InteractionOutboxItem(
        id: 'interaction_user_alpha_9780452284234',
        userId: 'user_alpha',
        isbn13: '9780452284234',
        interaction: 'finished',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        status: OutboxStatus.syncing,
      );

      await sharedBox.put(
        'outbox_interaction_user_alpha_9780452284234',
        jsonEncode(stuckItem.toJson()),
      );

      // New process startup
      final newProcessRepo = InteractionsOutboxRepository(sharedBox);
      final items = newProcessRepo.getPendingItems('user_alpha');

      expect(items.length, 1);
      expect(items.first.status, OutboxStatus.pending); // Automatically recovered to pending!
    });
  });
}
