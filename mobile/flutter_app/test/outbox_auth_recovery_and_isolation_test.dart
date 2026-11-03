import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/entities/favorite_outbox_item.dart';
import 'package:book_ai_app/domain/entities/interaction_outbox_item.dart';
import 'package:book_ai_app/data/repositories/favorites_outbox_repository.dart';
import 'package:book_ai_app/data/repositories/interactions_outbox_repository.dart';
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/providers/auth_provider.dart';
import 'package:book_ai_app/application/use_cases/manage_recommendations_use_case.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:book_ai_app/services/auth_service_base.dart';
import 'package:book_ai_app/services/supabase_service.dart';
import 'package:book_ai_app/services/sync_coordinator.dart';

// ---------------------------------------------------------------------------
// In-Memory Test Box Double
// ---------------------------------------------------------------------------

class TestInMemoryBox implements Box {
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

// ---------------------------------------------------------------------------
// Mock & Fake Implementations
// ---------------------------------------------------------------------------

class MockApiService implements ApiService {
  final List<Map<String, String>> feedbackCalls = [];
  Exception? feedbackException;
  bool returnSuccess = true;

  @override
  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    feedbackCalls.add({
      'userId': userId,
      'bookId': bookId,
      'interaction': interaction,
    });
    if (feedbackException != null) throw feedbackException!;
    return returnSuccess;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSupabaseService implements SupabaseService {
  User? mockUser;
  final List<Map<String, String>> addFavoriteCalls = [];
  final List<Map<String, String>> removeFavoriteCalls = [];
  Exception? error;
  final StreamController<List<Map<String, dynamic>>> _favoritesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  User? get currentUser => mockUser;

  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) =>
      _favoritesController.stream;

  void emitFavorites(List<Map<String, dynamic>> favs) {
    _favoritesController.add(favs);
  }

  void emitError(Object error) {
    _favoritesController.addError(error);
  }

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
    removeFavoriteCalls.add({'userId': userId, 'bookId': bookId});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthService implements AuthServiceBase {
  User? _currentUser;
  final StreamController<AuthState> _streamCtrl =
      StreamController<AuthState>.broadcast();

  @override
  User? get currentUser => _currentUser;

  @override
  bool get isConfigured => true;

  @override
  Stream<AuthState> get authStateStream => _streamCtrl.stream;

  void setMockUser(User? user) {
    _currentUser = user;
  }

  void emitAuthState(AuthState state) {
    _currentUser = state.session?.user;
    _streamCtrl.add(state);
  }

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final user = User(
      id: 'mock_uid_signed_in',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2023-01-01',
      email: email,
    );
    _currentUser = user;
    return AuthResponse(
      session: Session(
        accessToken: 'token_123',
        tokenType: 'bearer',
        user: user,
      ),
      user: user,
    );
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockBookRepository implements BookRepository {
  final List<String> clearedUsers = [];

  @override
  void clearUserCache(String userId) {
    clearedUsers.add(userId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockManageRecommendationsUseCase implements ManageRecommendationsUseCase {
  Exception? error;
  bool returnSuccess = true;
  final List<Map<String, String>> submitCalls = [];
  Completer<List<Book>>? delayedRecsCompleter;

  @override
  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    submitCalls.add({
      'userId': userId,
      'bookId': bookId,
      'interaction': interaction,
    });
    if (error != null) throw error!;
    return returnSuccess;
  }

  @override
  Future<List<Book>> getPersonalizedRecs(
      String userId, List<Book> fallbackBooks, {String? category, bool? excludeCompleted}) async {
    if (delayedRecsCompleter != null) {
      return await delayedRecsCompleter!.future;
    }
    if (error != null) throw error!;
    return [
      Book(
        isbn13: '978000000001',
        title: 'Rec Book for $userId',
        authors: 'Author',
        categories: 'Fiction',
        thumbnail: '',
        description: '',
        publishedDate: '2024',
        pageCount: 200,
        averageRating: 4.5,
        ratingsCount: 100,
      )
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LIBRIS Section 2: Outbox Auth-Recovery Verification', () {
    late TestInMemoryBox box;
    late InteractionsOutboxRepository intRepo;
    late MockApiService mockApi;

    setUp(() {
      box = TestInMemoryBox();
      intRepo = InteractionsOutboxRepository(box);
      mockApi = MockApiService();
    });

    test('Flow 1-5: User A offline queues interaction -> API 401 suspends -> reauth resets -> sync succeeds and clears outbox', () async {
      const userA = 'user_alpha_1';
      const isbn = '9780140449136';

      // 1. Kullanıcı A çevrimdışıyken etkileşim kuyruğa ekler
      await intRepo.enqueue(
        userId: userA,
        isbn13: isbn,
        interaction: 'finished',
      );

      var pending = intRepo.getPendingItems(userA);
      expect(pending.length, 1);
      expect(pending.first.status, OutboxStatus.pending);
      expect(pending.first.retryCount, 0);

      // 2. API 401 döndürür ve işlem auth nedeniyle askıya alınır
      mockApi.feedbackException = DioException(
        requestOptions: RequestOptions(path: '/api/feedback'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/feedback'),
          statusCode: 401,
          data: {'error': 'JWT expired or unauthorized'},
        ),
        type: DioExceptionType.badResponse,
        message: 'Server returned HTTP 401: Unauthorized',
      );

      final syncResult1 = await intRepo.syncUserOutbox(
        userId: userA,
        apiService: mockApi,
      );

      expect(syncResult1.synced, 0);
      expect(syncResult1.failed, 1);

      // Item should now be in permanentFailure due to auth
      var itemAfter401 = intRepo.getItem(userA, isbn);
      expect(itemAfter401, isNotNull);
      expect(itemAfter401!.status, OutboxStatus.permanentFailure);
      expect(itemAfter401.lastError?.toLowerCase(), contains('401'));

      // If sync runs again without re-auth, it must be skipped (queue paused)
      final syncResultSkipped = await intRepo.syncUserOutbox(
        userId: userA,
        apiService: mockApi,
      );
      expect(syncResultSkipped.skipped, 1);
      expect(syncResultSkipped.synced, 0);

      // 3 & 4. Kullanıcı A yeniden giriş yapar / token yenilenir -> resetAuthFailures
      await intRepo.resetAuthFailures(userA);

      var itemAfterReset = intRepo.getItem(userA, isbn);
      expect(itemAfterReset, isNotNull);
      expect(itemAfterReset!.status, OutboxStatus.pending);
      expect(itemAfterReset.retryCount, 0);
      expect(itemAfterReset.lastError, isNull);

      // 5. Senkronizasyon başarılıysa işlem kuyruktan kaldırılır
      mockApi.feedbackException = null; // API healthy & authenticated now
      mockApi.returnSuccess = true;

      final syncResultSuccess = await intRepo.syncUserOutbox(
        userId: userA,
        apiService: mockApi,
      );

      expect(syncResultSuccess.synced, 1);
      expect(syncResultSuccess.failed, 0);

      // Successfully purged from durable outbox
      expect(intRepo.hasPendingItem(userA, isbn), isFalse);
      expect(intRepo.getPendingItems(userA), isEmpty);
    });

    test('Flow 4: resetAuthFailures only restores auth-failed items, not client 400 validation failures', () async {
      const userA = 'user_alpha_1';

      // Seed 2 items: 1 auth failure (401), 1 client validation failure (400)
      final authItem = InteractionOutboxItem(
        id: 'int_1',
        userId: userA,
        isbn13: '9781111111111',
        interaction: 'like',
        createdAt: DateTime.now(),
        retryCount: 1,
        status: OutboxStatus.permanentFailure,
        lastError: 'HTTP 401: Unauthorized token',
      );
      final clientErrorItem = InteractionOutboxItem(
        id: 'int_2',
        userId: userA,
        isbn13: '9782222222222',
        interaction: 'unknown_action',
        createdAt: DateTime.now(),
        retryCount: 1,
        status: OutboxStatus.permanentFailure,
        lastError: 'HTTP 400: Bad request - invalid interaction payload',
      );

      await box.put('outbox_interaction_${userA}_9781111111111', jsonEncode(authItem.toJson()));
      await box.put('outbox_interaction_${userA}_9782222222222', jsonEncode(clientErrorItem.toJson()));

      // Invoke resetAuthFailures
      await intRepo.resetAuthFailures(userA);

      final resetAuth = intRepo.getItem(userA, '9781111111111');
      final untouchedClient = intRepo.getItem(userA, '9782222222222');

      expect(resetAuth!.status, OutboxStatus.pending);
      expect(resetAuth.retryCount, 0);
      expect(resetAuth.lastError, isNull);

      expect(untouchedClient!.status, OutboxStatus.permanentFailure);
      expect(untouchedClient.lastError, contains('400'));
    });

    test('Flow 6: Account isolation between User A and User B outbox queues', () async {
      const userA = 'user_alpha_1';
      const userB = 'user_beta_2';

      await intRepo.enqueue(userId: userA, isbn13: '978111', interaction: 'reading');
      await intRepo.enqueue(userId: userB, isbn13: '978222', interaction: 'finished');

      // Sync User B
      mockApi.returnSuccess = true;
      final syncResultB = await intRepo.syncUserOutbox(
        userId: userB,
        apiService: mockApi,
      );

      expect(syncResultB.synced, 1);
      expect(mockApi.feedbackCalls.length, 1);
      expect(mockApi.feedbackCalls.first['userId'], userB);
      expect(mockApi.feedbackCalls.first['bookId'], '978222');

      // User A's item is untouched and was NEVER sent under User B's identity
      expect(intRepo.hasPendingItem(userA, '978111'), isTrue);
      expect(intRepo.hasPendingItem(userB, '978222'), isFalse);
    });

    test('SyncCoordinator account mismatch guard blocks cross-user submission', () async {
      final favRepo = FavoritesOutboxRepository(box);
      final coordinator = SyncCoordinator(favRepo: favRepo, intRepo: intRepo);
      final mockSupabase = MockSupabaseService();

      const userA = 'user_alpha_1';
      const userB = 'user_beta_2';

      await intRepo.enqueue(userId: userA, isbn13: '978111', interaction: 'like');

      // Active session belongs to User B, but User A sync was triggered
      mockSupabase.mockUser = const User(
        id: userB,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2023-01-01',
      );

      final coordResult = await coordinator.syncAll(
        userId: userA,
        apiService: mockApi,
        supabaseService: mockSupabase,
      );

      // Blocked by Account Isolation Guard
      expect(coordResult.totalSynced, 0);
      expect(mockApi.feedbackCalls, isEmpty);
      expect(intRepo.hasPendingItem(userA, '978111'), isTrue);
    });

    test('resetAuthFailures is safe and idempotent across repeated calls', () async {
      const userA = 'user_alpha_1';
      final authItem = InteractionOutboxItem(
        id: 'int_1',
        userId: userA,
        isbn13: '978111',
        interaction: 'reading',
        createdAt: DateTime.now(),
        retryCount: 2,
        status: OutboxStatus.permanentFailure,
        lastError: 'HTTP 401: Token expired',
      );
      await box.put('outbox_interaction_${userA}_978111', jsonEncode(authItem.toJson()));

      // Call 5 times consecutively
      for (int i = 0; i < 5; i++) {
        await intRepo.resetAuthFailures(userA);
      }

      final item = intRepo.getItem(userA, '978111');
      expect(item!.status, OutboxStatus.pending);
      expect(item.retryCount, 0);
      expect(item.lastError, isNull);
    });
  });

  group('LIBRIS Section 3: HTTP Error Classification & Retry Policy', () {
    late TestInMemoryBox box;
    late InteractionsOutboxRepository intRepo;
    late MockManageRecommendationsUseCase mockUseCase;
    late RecommendationProvider provider;

    setUp(() {
      box = TestInMemoryBox();
      intRepo = InteractionsOutboxRepository(box);
      mockUseCase = MockManageRecommendationsUseCase();
      provider = RecommendationProvider(
        manageRecommendations: mockUseCase,
        outboxRepo: intRepo,
      );
    });

    test('Permanent invalid request 400/422 returns false, rolls back optimistic UI, and DOES NOT queue', () async {
      const userId = 'user_1';
      const bookId = '978111';

      // Throw 400 Bad Request
      mockUseCase.error = DioException(
        requestOptions: RequestOptions(path: '/api/feedback'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/feedback'),
          statusCode: 400,
          data: {'error': 'Invalid interaction: rating out of bounds'},
        ),
        type: DioExceptionType.badResponse,
        message: 'Server returned HTTP 400: Bad Request',
      );

      final success = await provider.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: 'dislike',
      );

      expect(success, isFalse);
      // Must NOT be queued into outbox
      expect(intRepo.hasPendingItem(userId, bookId), isFalse);
    });

    test('Permanent invalid request 422 Unprocessable Entity returns false and DOES NOT queue', () async {
      const userId = 'user_1';
      const bookId = '978111';

      mockUseCase.error = DioException(
        requestOptions: RequestOptions(path: '/api/feedback'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/feedback'),
          statusCode: 422,
          data: {'error': 'Validation failure on schema'},
        ),
        type: DioExceptionType.badResponse,
        message: 'Server returned HTTP 422: Unprocessable Entity',
      );

      final success = await provider.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: 'want_to_read',
      );

      expect(success, isFalse);
      expect(intRepo.hasPendingItem(userId, bookId), isFalse);
    });

    test('Auth 401/403: Enqueues into outbox and marks safely suspended in sync', () async {
      const userId = 'user_1';
      const bookId = '978111';

      // 401 on foreground submission
      mockUseCase.error = DioException(
        requestOptions: RequestOptions(path: '/api/feedback'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/feedback'),
          statusCode: 401,
          data: {'error': 'Unauthorized'},
        ),
        type: DioExceptionType.badResponse,
        message: 'Server returned HTTP 401: Unauthorized',
      );

      final success = await provider.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: 'like',
      );

      // Preserved in durable outbox
      expect(success, isTrue);
      expect(intRepo.hasPendingItem(userId, bookId), isTrue);

      // Now sync with continuing 401
      final mockApi = MockApiService();
      mockApi.feedbackException = mockUseCase.error;

      final syncResult = await intRepo.syncUserOutbox(
        userId: userId,
        apiService: mockApi,
      );

      expect(syncResult.failed, 1);
      final item = intRepo.getItem(userId, bookId);
      expect(item!.status, OutboxStatus.permanentFailure);
      expect(item.lastError?.toLowerCase(), contains('401'));
    });

    test('Transient server/rate-limit 429/5xx applies exponential backoff, capped at 5 retries', () async {
      const userId = 'user_1';
      const bookId = '978111';

      // Enqueue item
      await intRepo.enqueue(userId: userId, isbn13: bookId, interaction: 'reading');

      final mockApi = MockApiService();
      mockApi.feedbackException = DioException(
        requestOptions: RequestOptions(path: '/api/feedback'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/feedback'),
          statusCode: 429,
          data: {'error': 'Too many requests'},
        ),
        type: DioExceptionType.badResponse,
        message: 'Server returned HTTP 429: Too Many Requests',
      );

      // First failure: retryCount 1, backoff calculated
      await intRepo.syncUserOutbox(userId: userId, apiService: mockApi);
      var item = intRepo.getItem(userId, bookId);
      expect(item!.status, OutboxStatus.failed);
      expect(item.retryCount, 1);
      expect(item.nextAttemptAt, isNotNull);

      // Simulate reaching max retries (5)
      await intRepo.updateItem(item.copyWith(retryCount: 5));
      await intRepo.syncUserOutbox(userId: userId, apiService: mockApi);

      item = intRepo.getItem(userId, bookId);
      // Transferred to permanent failure after max retries exceeded to stop aggressive looping
      expect(item!.status, OutboxStatus.permanentFailure);
      expect(item.lastError, contains('Max retries (5) exceeded'));
    });

    test('Network outage/timeout: Preserved without data loss and idempotent', () async {
      const userId = 'user_1';
      const bookId = '978111';

      mockUseCase.error = DioException(
        requestOptions: RequestOptions(path: '/api/feedback'),
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timed out',
      );

      // First attempt
      final success1 = await provider.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: 'want_to_read',
      );
      expect(success1, isTrue);

      // Subsequent identical mutation coalesces idempotently
      final success2 = await provider.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: 'finished',
      );
      expect(success2, isTrue);

      final items = intRepo.getPendingItems(userId);
      expect(items.length, 1);
      expect(items.first.interaction, 'finished'); // Latest desired state preserved
    });
  });

  group('LIBRIS Section 4: Account Switching & Screen State Isolation', () {
    late TestInMemoryBox box;
    late FavoritesOutboxRepository favRepo;
    late MockSupabaseService mockSupabase;
    late FavoritesProvider favProvider;
    late MockManageRecommendationsUseCase mockRecUseCase;
    late RecommendationProvider recProvider;

    setUp(() {
      box = TestInMemoryBox();
      favRepo = FavoritesOutboxRepository(box);
      mockSupabase = MockSupabaseService();
      favProvider = FavoritesProvider(mockSupabase, favRepo);
      mockRecUseCase = MockManageRecommendationsUseCase();
      recProvider = RecommendationProvider(
        manageRecommendations: mockRecUseCase,
        outboxRepo: InteractionsOutboxRepository(box),
      );
    });

    test('User A logout & User B login: Favorites and Recommendations are not visible to B', () async {
      const userA = 'user_A';
      const userB = 'user_B';

      // 1. User A loads favorites
      await favProvider.loadFavorites(userA);
      mockSupabase.emitFavorites([
        {'id': 'fav_1', 'user_id': userA, 'isbn13': '9780001', 'title': 'Book A', 'author': 'Author A'}
      ]);
      await pumpEventQueue();

      expect(favProvider.favorites.length, 1);
      expect(favProvider.favorites.first.isbn13, '9780001');

      // 2. User A loads recommendations
      await recProvider.fetchPersonalizedRecs(userA, []);
      expect(recProvider.personalizedRecs.length, 1);
      expect(recProvider.personalizedRecs.first.title, contains(userA));

      // 3. User A logs out
      favProvider.clearFavorites();
      recProvider.clearUserData();

      expect(favProvider.favorites, isEmpty);
      expect(favProvider.activeUserId, isNull);
      expect(recProvider.personalizedRecs, isEmpty);
      expect(recProvider.status, RecommendationStatus.initial);

      // 4. User B logs in and loads their favorites
      await favProvider.loadFavorites(userB);
      mockSupabase.emitFavorites([
        {'id': 'fav_2', 'user_id': userB, 'isbn13': '9780002', 'title': 'Book B', 'author': 'Author B'}
      ]);
      await pumpEventQueue();

      expect(favProvider.favorites.length, 1);
      expect(favProvider.favorites.first.isbn13, '9780002');
      expect(favProvider.favorites.any((b) => b.isbn13 == '9780001'), isFalse);
    });

    test('Token refresh for same user does NOT clear cache', () async {
      final mockAuthSvc = MockAuthService();
      final mockBookRepo = MockBookRepository();

      const userA = 'user_A';
      const userObj = User(
        id: userA,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2023-01-01',
      );
      mockAuthSvc.setMockUser(userObj);

      final authProvider = AuthProvider(mockAuthSvc, bookRepository: mockBookRepo);
      await pumpEventQueue();

      expect(authProvider.currentUser?.id, userA);

      // Emit token refresh event for the same user
      mockAuthSvc.emitAuthState(AuthState(
        AuthChangeEvent.tokenRefreshed,
        Session(
          accessToken: 'fresh_jwt_token',
          tokenType: 'bearer',
          user: userObj,
        ),
      ));
      await pumpEventQueue();

      // Cache MUST NOT be cleared
      expect(mockBookRepo.clearedUsers, isEmpty);
    });

    test('Stale delayed response from User A does NOT overwrite User B state in RecommendationProvider', () async {
      const userA = 'user_A';
      const userB = 'user_B';

      final completerA = Completer<List<Book>>();
      mockRecUseCase.delayedRecsCompleter = completerA;

      // Start fetching for User A (delayed)
      final futureA = recProvider.fetchPersonalizedRecs(userA, []);

      // User switches to B while A is still awaiting network
      mockRecUseCase.delayedRecsCompleter = null; // B returns immediately
      await recProvider.fetchPersonalizedRecs(userB, []);

      expect(recProvider.personalizedRecs.first.title, contains(userB));

      // Now User A's stale response finally finishes
      completerA.complete(const [
        Book(
          isbn13: '978999',
          title: 'Stale Book for User A',
          authors: 'Stale Author',
          categories: 'Fiction',
          thumbnail: '',
          description: '',
          publishedDate: '2020',
          pageCount: 300,
          averageRating: 4.0,
          ratingsCount: 50,
        )
      ]);
      await futureA;

      // Stale response MUST be ignored; User B's state remains intact
      expect(recProvider.personalizedRecs.first.title, contains(userB));
      expect(recProvider.personalizedRecs.any((b) => b.title.contains('Stale')), isFalse);
    });

    test('Stale delayed stream emission from User A does NOT overwrite User B in FavoritesProvider', () async {
      const userA = 'user_A';
      const userB = 'user_B';

      await favProvider.loadFavorites(userA);

      // Switch to User B
      await favProvider.loadFavorites(userB);

      // Late stream event arrives referencing User A
      mockSupabase.emitFavorites([
        {'id': 'fav_stale', 'user_id': userA, 'isbn13': '978stale', 'title': 'Stale User A Fav', 'author': 'Author'}
      ]);
      await pumpEventQueue();

      // Must be ignored because activeUserId is userB
      expect(favProvider.activeUserId, userB);
    });
  });

  group('LIBRIS Section 5: Senior Release Gate Closure & Invariant Regressions', () {
    late TestInMemoryBox box;
    late InteractionsOutboxRepository intRepo;
    late FavoritesOutboxRepository favRepo;
    late MockApiService mockApi;
    late MockSupabaseService mockSupabase;
    late SyncCoordinator coordinator;

    setUp(() {
      box = TestInMemoryBox();
      intRepo = InteractionsOutboxRepository(box);
      favRepo = FavoritesOutboxRepository(box);
      mockApi = MockApiService();
      mockSupabase = MockSupabaseService();
      coordinator = SyncCoordinator(favRepo: favRepo, intRepo: intRepo);
    });

    test('Invariant 1: 403 Forbidden is NOT reset by resetAuthFailures or token refresh', () async {
      const userA = 'user_alpha_1';
      final forbiddenItem = InteractionOutboxItem(
        id: 'int_403',
        userId: userA,
        isbn13: '9783333333333',
        interaction: 'dislike',
        createdAt: DateTime.now(),
        retryCount: 1,
        status: OutboxStatus.permanentFailure,
        lastError: 'HTTP 403: Forbidden - Insufficient user permissions',
      );
      final auth401Item = InteractionOutboxItem(
        id: 'int_401',
        userId: userA,
        isbn13: '9784444444444',
        interaction: 'like',
        createdAt: DateTime.now(),
        retryCount: 1,
        status: OutboxStatus.permanentFailure,
        lastError: 'HTTP 401: Unauthorized token expired',
      );

      await box.put('outbox_interaction_${userA}_9783333333333', jsonEncode(forbiddenItem.toJson()));
      await box.put('outbox_interaction_${userA}_9784444444444', jsonEncode(auth401Item.toJson()));

      // Trigger token refresh reset
      await intRepo.resetAuthFailures(userA);

      final item403 = intRepo.getItem(userA, '9783333333333');
      final item401 = intRepo.getItem(userA, '9784444444444');

      // 403 Forbidden MUST remain in permanentFailure to prevent infinite retry loop
      expect(item403!.status, OutboxStatus.permanentFailure);
      expect(item403.lastError, contains('403'));

      // 401 Unauthorized is properly restored to pending
      expect(item401!.status, OutboxStatus.pending);
      expect(item401.lastError, isNull);
    });

    test('Invariant 2: 429 Too Many Requests evaluates Retry-After header for backoff timing', () async {
      const userA = 'user_alpha_1';
      const isbn = '9785555555555';
      await intRepo.enqueue(userId: userA, isbn13: isbn, interaction: 'reading');

      mockApi.feedbackException = DioException(
        requestOptions: RequestOptions(path: '/api/feedback'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/feedback'),
          statusCode: 429,
          headers: Headers.fromMap({
            'retry-after': ['45'],
          }),
          data: {'error': 'Rate limited'},
        ),
        type: DioExceptionType.badResponse,
        message: 'Server returned HTTP 429: Rate limited',
      );

      final beforeSync = DateTime.now();
      await intRepo.syncUserOutbox(userId: userA, apiService: mockApi);

      final item = intRepo.getItem(userA, isbn);
      expect(item!.status, OutboxStatus.failed);
      expect(item.nextAttemptAt, isNotNull);

      // Verify that nextAttemptAt honors the 45-second Retry-After header (+/- 5 seconds tolerance)
      final scheduledDelaySeconds = item.nextAttemptAt!.difference(beforeSync).inSeconds;
      expect(scheduledDelaySeconds, greaterThanOrEqualTo(40));
      expect(scheduledDelaySeconds, lessThanOrEqualTo(50));
    });

    test('Invariant 3: SyncCoordinator blocks sync when session is unauthenticated (currentUser is null)', () async {
      const userA = 'user_alpha_1';
      await intRepo.enqueue(userId: userA, isbn13: '9786666666666', interaction: 'finished');
      await favRepo.enqueue(
        userId: userA,
        isbn13: '9786666666666',
        action: OutboxAction.add,
        bookTitle: 'Test Book',
        bookAuthor: 'Test Author',
        bookImageUrl: null,
      );

      // Session is completely logged out (null)
      mockSupabase.mockUser = null;

      final result = await coordinator.syncAll(
        userId: userA,
        apiService: mockApi,
        supabaseService: mockSupabase,
      );

      // Blocked from sending unauthenticated network calls
      expect(result.totalSynced, 0);
      expect(mockApi.feedbackCalls, isEmpty);
      expect(mockSupabase.addFavoriteCalls, isEmpty);

      // Both items remain safely in outbox without being marked failed
      expect(intRepo.hasPendingItem(userA, '9786666666666'), isTrue);
      expect(favRepo.hasPendingItem(userA, '9786666666666'), isTrue);
    });

    test('Invariant 4: Application restart recovers in-flight syncing items and keeps queue bound to user', () async {
      const userA = 'user_alpha_1';
      const isbn = '9787777777777';

      // Simulate a crashed/interrupted sync item stuck in syncing state
      final stuckItem = InteractionOutboxItem(
        id: 'int_stuck',
        userId: userA,
        isbn13: isbn,
        interaction: 'want_to_read',
        createdAt: DateTime.now(),
        retryCount: 0,
        status: OutboxStatus.syncing,
      );
      await box.put('outbox_interaction_${userA}_$isbn', jsonEncode(stuckItem.toJson()));

      // Fresh repository instance simulating app restart
      final freshRepo = InteractionsOutboxRepository(box);

      // Item should be cleanly recovered to pending
      final recoveredItem = freshRepo.getItem(userA, isbn);
      expect(recoveredItem!.status, OutboxStatus.pending);
      expect(recoveredItem.userId, userA);

      final pendingList = freshRepo.getPendingItems(userA);
      expect(pendingList.length, 1);
      expect(pendingList.first.status, OutboxStatus.pending);
    });

    test('Invariant 5: Rapid repeated resume/sync trigger events do not cause duplicate submissions', () async {
      const userA = 'user_alpha_1';
      await favRepo.enqueue(
        userId: userA,
        isbn13: '9788888888888',
        action: OutboxAction.add,
        bookTitle: 'Concurrency Book',
        bookAuthor: 'Author',
        bookImageUrl: null,
      );

      mockSupabase.mockUser = const User(
        id: userA,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2023-01-01',
      );

      // Fire 5 concurrent sync requests simulating simultaneous app resume, network restore, and timer
      final futures = List.generate(5, (_) => coordinator.syncAll(
        userId: userA,
        apiService: mockApi,
        supabaseService: mockSupabase,
      ));

      final results = await Future.wait(futures);
      final totalSyncedAcrossAll = results.fold<int>(0, (sum, r) => sum + r.totalSynced);

      // Exactly 1 execution must perform the network call, and 4 must be skipped safely
      expect(totalSyncedAcrossAll, 1);
      expect(mockSupabase.addFavoriteCalls.length, 1);
      expect(favRepo.getPendingItems(userA), isEmpty);
    });
  });
}
