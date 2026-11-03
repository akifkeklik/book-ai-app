import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:book_ai_app/data/repositories/favorites_outbox_repository.dart';
import 'package:book_ai_app/data/repositories/interactions_outbox_repository.dart';
import 'package:book_ai_app/domain/entities/favorite_outbox_item.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:book_ai_app/services/background_sync_manager.dart';
import 'package:book_ai_app/services/supabase_service.dart';
import 'package:book_ai_app/services/sync_coordinator.dart';

// ── Mock & Fake Services for Deterministic Testing ───────────────────────────

class FakeSupabaseService implements SupabaseService {
  String? mockUserId;
  final Set<String> remoteFavorites = {};
  int addCalls = 0;
  int removeCalls = 0;
  bool shouldThrow = false;
  bool throwAuthError = false;

  FakeSupabaseService({this.mockUserId = 'user_alpha'});

  @override
  User? get currentUser {
    if (mockUserId == null) return null;
    return User(
      id: mockUserId!,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  String? get currentUserId => mockUserId;

  @override
  Future<void> addFavorite({
    required String userId,
    required String bookId,
    required String title,
    required String author,
    required String? imageUrl,
  }) async {
    addCalls++;
    if (throwAuthError) throw const AuthApiException('Invalid JWT token', statusCode: '401');
    if (shouldThrow) throw const SocketException('Connection refused');
    remoteFavorites.add(bookId);
  }

  @override
  Future<void> removeFavorite(String userId, String bookId) async {
    removeCalls++;
    if (throwAuthError) throw const AuthApiException('Invalid JWT token', statusCode: '401');
    if (shouldThrow) throw const SocketException('Connection refused');
    remoteFavorites.remove(bookId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApiService implements ApiService {
  final Map<String, String> remoteInteractions = {};
  int submitCalls = 0;
  bool shouldThrow = false;
  bool throwAuthError = false;
  bool throwClient4xx = false;

  @override
  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    submitCalls++;
    if (throwAuthError) throw Exception('401 Unauthorized: invalid token');
    if (throwClient4xx) throw Exception('400 Bad Request: invalid entity id');
    if (shouldThrow) throw const SocketException('Network is unreachable');

    if (interaction == 'clear' || interaction == 'remove') {
      remoteInteractions.remove(bookId);
    } else {
      remoteInteractions[bookId] = interaction;
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box favBox;
  late Box intBox;
  late FavoritesOutboxRepository favRepo;
  late InteractionsOutboxRepository intRepo;
  late SyncCoordinator coordinator;
  late FakeSupabaseService fakeSupabase;
  late FakeApiService fakeApi;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('libris_bg_sync_test_');
    Hive.init(tempDir.path);

    favBox = await Hive.openBox('favorites_outbox_test');
    intBox = await Hive.openBox('interactions_outbox_test');

    favRepo = FavoritesOutboxRepository(favBox);
    intRepo = InteractionsOutboxRepository(intBox);

    coordinator = SyncCoordinator(
      favRepo: favRepo,
      intRepo: intRepo,
    );

    fakeSupabase = FakeSupabaseService(mockUserId: 'user_alpha');
    fakeApi = FakeApiService();
  });

  tearDown(() async {
    await favBox.close();
    await intBox.close();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Workstream B: Native Background Sync Coordinator & Invariants', () {
    test('1. Favorites and reading status queues are synchronized together in single cycle', () async {
      // Enqueue favorite operation
      await favRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000001',
        action: OutboxAction.add,
        bookTitle: 'Dune',
        bookAuthor: 'Frank Herbert',
        bookImageUrl: null,
      );

      // Enqueue interaction operation
      await intRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000002',
        interaction: 'reading',
      );

      expect(favRepo.getPendingItems('user_alpha').length, 1);
      expect(intRepo.getPendingItems('user_alpha').length, 1);

      final result = await coordinator.syncAll(
        userId: 'user_alpha',
        apiService: fakeApi,
        supabaseService: fakeSupabase,
      );

      expect(result.totalSynced, 2);
      expect(result.totalFailed, 0);
      expect(result.favResult.synced, 1);
      expect(result.intResult.synced, 1);
      expect(fakeSupabase.remoteFavorites.contains('9780000000001'), isTrue);
      expect(fakeApi.remoteInteractions['9780000000002'], 'reading');

      // Both outbox queues are drained
      expect(favRepo.getPendingItems('user_alpha').isEmpty, isTrue);
      expect(intRepo.getPendingItems('user_alpha').isEmpty, isTrue);
    });

    test('2. Account Isolation: User A queue is NEVER sent using User B credentials', () async {
      // Enqueue operations for User Alpha
      await favRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000001',
        action: OutboxAction.add,
        bookTitle: 'Dune',
        bookAuthor: 'Frank Herbert',
        bookImageUrl: null,
      );
      await intRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000002',
        interaction: 'reading',
      );

      // Active Supabase session is User Beta (account switched!)
      final switchedSupabase = FakeSupabaseService(mockUserId: 'user_beta');

      final result = await coordinator.syncAll(
        userId: 'user_alpha',
        apiService: fakeApi,
        supabaseService: switchedSupabase,
      );

      // Must be safely blocked without executing network calls!
      expect(result.totalSynced, 0);
      expect(switchedSupabase.addCalls, 0);
      expect(fakeApi.submitCalls, 0);

      // User Alpha items remain preserved and untouched in the queue
      expect(favRepo.getPendingItems('user_alpha').length, 1);
      expect(intRepo.getPendingItems('user_alpha').length, 1);
    });

    test('3. Concurrency & Overlapping Sync Guard: Second caller is safely skipped', () async {
      await favRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000001',
        action: OutboxAction.add,
        bookTitle: 'Dune',
        bookAuthor: 'Frank Herbert',
        bookImageUrl: null,
      );

      // Simulate concurrent sync calls
      final syncFuture1 = coordinator.syncAll(
        userId: 'user_alpha',
        apiService: fakeApi,
        supabaseService: fakeSupabase,
      );

      final syncFuture2 = coordinator.syncAll(
        userId: 'user_alpha',
        apiService: fakeApi,
        supabaseService: fakeSupabase,
      );

      final results = await Future.wait([syncFuture1, syncFuture2]);
      final totalSyncedAcrossCalls = results[0].totalSynced + results[1].totalSynced;

      expect(totalSyncedAcrossCalls, 1, reason: 'Duplicate sync execution must not fire duplicate network calls');
      expect(fakeSupabase.addCalls, 1);
    });

    test('4. Network Failure & Exponential Backoff: Failed items marked failed with scheduled retry', () async {
      fakeApi.shouldThrow = true;
      fakeSupabase.shouldThrow = true;

      await favRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000001',
        action: OutboxAction.add,
        bookTitle: 'Dune',
        bookAuthor: 'Frank Herbert',
        bookImageUrl: null,
      );
      await intRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000002',
        interaction: 'reading',
      );

      final result = await coordinator.syncAll(
        userId: 'user_alpha',
        apiService: fakeApi,
        supabaseService: fakeSupabase,
      );

      expect(result.totalSynced, 0);
      expect(result.totalFailed, 2);

      final favItem = favRepo.getItem('user_alpha', '9780000000001');
      final intItem = intRepo.getItem('user_alpha', '9780000000002');

      expect(favItem?.status, OutboxStatus.failed);
      expect(favItem?.retryCount, 1);
      expect(favItem?.nextAttemptAt, isNotNull);

      expect(intItem?.status, OutboxStatus.failed);
      expect(intItem?.retryCount, 1);
      expect(intItem?.nextAttemptAt, isNotNull);
    });

    test('5. Expired Auth Handling: Marks permanent failure and pauses queue until re-auth', () async {
      fakeApi.throwAuthError = true;
      fakeSupabase.throwAuthError = true;

      await favRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000001',
        action: OutboxAction.add,
        bookTitle: 'Dune',
        bookAuthor: 'Frank Herbert',
        bookImageUrl: null,
      );
      await intRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000002',
        interaction: 'reading',
      );

      await coordinator.syncAll(
        userId: 'user_alpha',
        apiService: fakeApi,
        supabaseService: fakeSupabase,
      );

      final favItem = favRepo.getItem('user_alpha', '9780000000001');
      final intItem = intRepo.getItem('user_alpha', '9780000000002');

      expect(favItem?.status, OutboxStatus.permanentFailure);
      expect(intItem?.status, OutboxStatus.permanentFailure);

      // Verify diagnostics surface auth category
      final diagnostics = coordinator.getDiagnostics('user_alpha');
      expect(diagnostics.failureCategory, FailureCategory.auth);
      expect(diagnostics.queueDepth, 2);
    });

    test('6. Model A Contract: Clearing reading status preserves favorite state', () async {
      // 1. First sync favorite
      await favRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000001',
        action: OutboxAction.add,
        bookTitle: 'Dune',
        bookAuthor: 'Frank Herbert',
        bookImageUrl: null,
      );
      await coordinator.syncAll(
        userId: 'user_alpha',
        apiService: fakeApi,
        supabaseService: fakeSupabase,
      );
      expect(fakeSupabase.remoteFavorites.contains('9780000000001'), isTrue);

      // 2. Clear reading status on the same book
      await intRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000001',
        interaction: 'clear',
      );
      final clearResult = await coordinator.syncAll(
        userId: 'user_alpha',
        apiService: fakeApi,
        supabaseService: fakeSupabase,
      );

      expect(clearResult.totalSynced, 1);
      // Favorite record is 100% intact!
      expect(fakeSupabase.remoteFavorites.contains('9780000000001'), isTrue);
    });

    test('7. Privacy-safe Diagnostics: Queue depth, retries, and failure category without secrets', () async {
      await favRepo.enqueue(
        userId: 'user_alpha',
        isbn13: '9780000000001',
        action: OutboxAction.add,
        bookTitle: 'Dune',
        bookAuthor: 'Frank Herbert',
        bookImageUrl: null,
      );

      final diag = coordinator.getDiagnostics('user_alpha');
      expect(diag.queueDepth, 1);
      expect(diag.favoritesPending, 1);
      expect(diag.interactionsPending, 0);
      expect(diag.failureCategory, FailureCategory.none);

      final diagStr = diag.toString();
      expect(diagStr.contains('Dune'), isFalse, reason: 'Private titles/tokens must not be in summary');
      expect(diagStr.contains('Bearer'), isFalse);
    });

    test('8. BackgroundSyncManager platform checks and registration safety', () async {
      final isSupported = BackgroundSyncManager.isSupportedPlatform;
      expect(isSupported, isA<bool>());

      await BackgroundSyncManager.cancelAll();
      expect(BackgroundSyncManager.isRegistered, isFalse);
    });
  });
}
