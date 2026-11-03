import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/entities/favorite_outbox_item.dart';
import 'package:book_ai_app/data/repositories/favorites_outbox_repository.dart';
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/providers/auth_provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/screens/favorites_screen.dart';
import 'package:book_ai_app/services/supabase_service.dart';
import 'package:book_ai_app/services/auth_service_base.dart';

// ---------------------------------------------------------------------------
// Fakes & Test Doubles
// ---------------------------------------------------------------------------

class FakeBox implements Box {
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

class MockOutboxSupabaseService implements SupabaseService {
  final _favoritesStreamController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  final List<Map<String, dynamic>> _mockDb = [];
  final List<Map<String, String>> addFavoriteCalls = [];
  final List<Map<String, String>> removeFavoriteCalls = [];

  Exception? errorToAdd;
  Exception? errorToRemove;
  bool simulateAuth401Error = false;
  bool simulateLostResponseOnAdd = false;
  Completer<void>? delaySyncCompleter;

  void pushStreamUpdate() {
    _favoritesStreamController.add(List.from(_mockDb));
  }

  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) {
    return _favoritesStreamController.stream;
  }

  @override
  Future<void> addFavorite({
    required String userId,
    required String bookId,
    required String title,
    required String author,
    required String? imageUrl,
  }) async {
    if (delaySyncCompleter != null) {
      await delaySyncCompleter!.future;
    }

    addFavoriteCalls.add({
      'userId': userId,
      'bookId': bookId,
      'title': title,
      'author': author,
      'imageUrl': imageUrl ?? '',
    });

    if (simulateAuth401Error) {
      throw const AuthApiException('Invalid JWT token', statusCode: '401');
    }

    if (errorToAdd != null) {
      throw errorToAdd!;
    }

    // Upsert behavior: replace if exists, otherwise insert
    _mockDb.removeWhere((item) =>
        item['book_id'] == bookId && item['user_id'] == userId);
    _mockDb.insert(0, {
      'id': 'db_id_$bookId',
      'user_id': userId,
      'book_id': bookId,
      'book_title': title,
      'book_author': author,
      'book_image_url': imageUrl,
      'added_at': DateTime.now().toIso8601String(),
    });

    if (simulateLostResponseOnAdd) {
      // Operation was applied on server DB, but network dropped during response
      throw const SocketException('Connection reset by peer during response');
    }

    pushStreamUpdate();
  }

  @override
  Future<void> removeFavorite(String userId, String bookId) async {
    removeFavoriteCalls.add({
      'userId': userId,
      'bookId': bookId,
    });

    if (simulateAuth401Error) {
      throw const AuthApiException('Forbidden', statusCode: '403');
    }

    if (errorToRemove != null) {
      throw errorToRemove!;
    }

    _mockDb.removeWhere((item) =>
        item['book_id'] == bookId && item['user_id'] == userId);
    pushStreamUpdate();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestAuthService implements AuthServiceBase {
  User? _currentUser;
  final _ctrl = StreamController<AuthState>.broadcast();

  FakeTestAuthService([this._currentUser]);

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<AuthState> get authStateStream => _ctrl.stream;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    _currentUser = User(
      id: email == 'userB@libris.com' ? 'user_b' : 'user_a',
      email: email,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    _ctrl.add(AuthState(AuthChangeEvent.signedIn, Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: _currentUser!,
    )));
    return AuthResponse(user: _currentUser);
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return signIn(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _ctrl.add(const AuthState(AuthChangeEvent.signedOut, null));
  }
}

Book createTestBook({
  required String isbn,
  required String title,
  String author = 'Test Author',
  String thumbnail = 'https://example.com/cover.jpg',
}) {
  return Book(
    isbn13: isbn,
    title: title,
    authors: author,
    categories: 'Fiction',
    description: 'A test book description',
    thumbnail: thumbnail,
    averageRating: 4.5,
    ratingsCount: 120,
    publishedDate: '2024',
    pageCount: 300,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBox fakeBox;
  late FavoritesOutboxRepository outboxRepo;
  late MockOutboxSupabaseService supabaseService;

  setUp(() {
    fakeBox = FakeBox();
    outboxRepo = FavoritesOutboxRepository(fakeBox);
    supabaseService = MockOutboxSupabaseService();
  });

  group('1. Offline Favorites Outbox Persistence', () {
    test('Çevrimdışı ekleme kalıcı kuyruğa yazılır ve iyimser güncelleme korunur', () async {
      // Arrange: simulate network down
      supabaseService.errorToAdd = const SocketException('No route to host');
      final provider = FavoritesProvider(supabaseService, outboxRepo);
      provider.loadFavorites('user_a');

      final book = createTestBook(isbn: '9780001', title: 'Offline Book');

      // Act
      await provider.toggleFavorite(userId: 'user_a', book: book);

      // Assert: Optimistic update is retained
      expect(provider.isFavorite('9780001'), isTrue);
      expect(provider.hasPendingSync('9780001'), isTrue);
      expect(provider.pendingSyncCount, 1);

      // Assert: Persisted in Hive FakeBox
      final item = outboxRepo.getItem('user_a', '9780001');
      expect(item, isNotNull);
      expect(item!.action, OutboxAction.add);
      expect(item.status, OutboxStatus.pending);
      expect(item.bookTitle, 'Offline Book');
      expect(item.isbn13, '9780001');

      provider.dispose();
    });

    test('Sunucu doğrulama hatasında iyimser güncelleme geri alınır (rollback)', () async {
      // Arrange: Server rejects request with validation / business logic failure
      supabaseService.errorToAdd = Exception('Add failed: invalid book entity');
      final provider = FavoritesProvider(supabaseService, outboxRepo);
      provider.loadFavorites('user_a');

      final book = createTestBook(isbn: '9780002', title: 'Invalid Book');

      // Act
      await provider.toggleFavorite(userId: 'user_a', book: book);

      // Assert: Optimistic update rolled back, not stored in outbox
      expect(provider.isFavorite('9780002'), isFalse);
      expect(provider.hasPendingSync('9780002'), isFalse);
      expect(provider.error, isNotNull);
      expect(outboxRepo.getItem('user_a', '9780002'), isNull);

      provider.dispose();
    });
  });

  group('2. Outbox Coalescing & Net Final State', () {
    test('Çevrimdışı ekle -> sil dizisi kuyruktan temizlenir (gereksiz istek engellenir)', () async {
      supabaseService.errorToAdd = const SocketException('Network down');
      supabaseService.errorToRemove = const SocketException('Network down');
      final provider = FavoritesProvider(supabaseService, outboxRepo);
      provider.loadFavorites('user_a');

      final book = createTestBook(isbn: '9780003', title: 'Coalesce Book');

      // Step 1: Add offline
      await provider.toggleFavorite(userId: 'user_a', book: book);
      expect(provider.isFavorite('9780003'), isTrue);
      expect(provider.pendingSyncCount, 1);
      expect(outboxRepo.getItem('user_a', '9780003')?.action, OutboxAction.add);

      // Step 2: Remove offline while still pending
      await provider.toggleFavorite(userId: 'user_a', book: book);
      expect(provider.isFavorite('9780003'), isFalse);

      // Assert: Coalesced! Because the book was never on the remote server,
      // adding then removing cancels both out completely.
      expect(provider.pendingSyncCount, 0);
      expect(provider.hasPendingSync('9780003'), isFalse);
      expect(outboxRepo.getItem('user_a', '9780003'), isNull);

      provider.dispose();
    });

    test('Sunucudaki kitabı çevrimdışı sil -> ekle dizisi nihai durumu korur', () async {
      // Arrange: Book exists on server
      supabaseService._mockDb.add({
        'id': 'fav_10',
        'user_id': 'user_a',
        'book_id': '9780004',
        'book_title': 'Existing Server Book',
        'book_author': 'Author',
        'book_image_url': '',
        'added_at': DateTime.now().toIso8601String(),
      });

      supabaseService.errorToAdd = const SocketException('Network offline');
      supabaseService.errorToRemove = const SocketException('Network offline');

      final provider = FavoritesProvider(supabaseService, outboxRepo);
      provider.loadFavorites('user_a');
      supabaseService.pushStreamUpdate();
      await Future.delayed(Duration.zero);

      expect(provider.isFavorite('9780004'), isTrue);

      final book = createTestBook(isbn: '9780004', title: 'Existing Server Book');

      // Step 1: Remove offline -> creates pending remove
      await provider.toggleFavorite(userId: 'user_a', book: book);
      expect(provider.isFavorite('9780004'), isFalse);
      expect(outboxRepo.getItem('user_a', '9780004')?.action, OutboxAction.remove);

      // Step 2: Re-add offline -> coalesces to cancellation (stays on server)
      await provider.toggleFavorite(userId: 'user_a', book: book);
      expect(provider.isFavorite('9780004'), isTrue);
      expect(outboxRepo.getItem('user_a', '9780004'), isNull);
      expect(provider.pendingSyncCount, 0);

      provider.dispose();
    });

    test('Çevrimdışı ekle -> sil -> ekle dizisi tek bir nihai ekleme işlemine indirgenir', () async {
      supabaseService.errorToAdd = const SocketException('Network down');
      supabaseService.errorToRemove = const SocketException('Network down');
      final provider = FavoritesProvider(supabaseService, outboxRepo);
      provider.loadFavorites('user_a');

      final book = createTestBook(isbn: '9780005', title: 'Triple Toggle Book');

      // Ekle
      await provider.toggleFavorite(userId: 'user_a', book: book);
      expect(outboxRepo.getItem('user_a', '9780005')?.action, OutboxAction.add);

      // Sil
      await provider.toggleFavorite(userId: 'user_a', book: book);
      expect(outboxRepo.getItem('user_a', '9780005'), isNull);

      // Yeniden Ekle
      await provider.toggleFavorite(userId: 'user_a', book: book);
      expect(outboxRepo.getItem('user_a', '9780005')?.action, OutboxAction.add);
      expect(provider.pendingSyncCount, 1);

      provider.dispose();
    });
  });

  group('3. Application Restart & Queue Restoration', () {
    test('Uygulama yeniden başladığında bekleyen işlemler ve disk önbelleği geri yüklenir', () async {
      // Step 1: Pre-populate fakeBox with cached favorites snapshot and outbox pending items
      final cachedFavorites = [
        {
          'id': 'fav_1',
          'user_id': 'user_a',
          'book_id': '9781111',
          'book_title': 'Cached Book 1',
          'book_author': 'Author 1',
          'book_image_url': '',
          'added_at': '2024-01-01T00:00:00.000Z',
        },
        {
          'id': 'fav_2',
          'user_id': 'user_a',
          'book_id': '9782222',
          'book_title': 'Cached Book 2',
          'book_author': 'Author 2',
          'book_image_url': '',
          'added_at': '2024-01-02T00:00:00.000Z',
        },
      ];
      await fakeBox.put('favorites_cache_user_a', jsonEncode(cachedFavorites));

      // Outbox item 1: Pending addition of book 3
      final outboxAdd = FavoriteOutboxItem(
        id: 'user_a_9783333',
        userId: 'user_a',
        isbn13: '9783333',
        action: OutboxAction.add,
        bookTitle: 'Offline Added Book 3',
        bookAuthor: 'Author 3',
        bookImageUrl: '',
        createdAt: DateTime.now(),
      );
      await fakeBox.put('outbox_user_a_9783333', jsonEncode(outboxAdd.toJson()));

      // Outbox item 2: Pending removal of book 2
      final outboxRemove = FavoriteOutboxItem(
        id: 'user_a_9782222',
        userId: 'user_a',
        isbn13: '9782222',
        action: OutboxAction.remove,
        bookTitle: 'Cached Book 2',
        bookAuthor: 'Author 2',
        bookImageUrl: '',
        createdAt: DateTime.now(),
      );
      await fakeBox.put('outbox_user_a_9782222', jsonEncode(outboxRemove.toJson()));

      // Step 2: Launch brand new FavoritesProvider (simulating app cold start)
      final newProvider = FavoritesProvider(supabaseService, outboxRepo);
      newProvider.loadFavorites('user_a');

      // Assert: Cached items were loaded immediately
      expect(newProvider.favorites.any((f) => f.isbn13 == '9781111'), isTrue);
      // Assert: Outbox removal was overlaid (book 2 is NOT present)
      expect(newProvider.favorites.any((f) => f.isbn13 == '9782222'), isFalse);
      // Assert: Outbox addition was overlaid (book 3 is present)
      expect(newProvider.favorites.any((f) => f.isbn13 == '9783333'), isTrue);
      expect(newProvider.isFavorite('9783333'), isTrue);
      expect(newProvider.hasPendingSync('9783333'), isTrue);
      expect(newProvider.pendingSyncCount, 2);

      newProvider.dispose();
    });
  });

  group('4. Safe Synchronization on Connectivity Restoration', () {
    test('Bağlantı geri geldiğinde outbox işlemleri güvenle sunucuya gönderilir ve kuyruk temizlenir', () async {
      // Arrange: Seed outbox with 1 add and 1 remove
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '9785555',
        action: OutboxAction.add,
        bookTitle: 'Sync Book Add',
        bookAuthor: 'Author',
        bookImageUrl: null,
      );
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '9786666',
        action: OutboxAction.remove,
        bookTitle: 'Sync Book Remove',
        bookAuthor: 'Author',
        bookImageUrl: null,
      );

      expect(outboxRepo.getPendingItems('user_a').length, 2);

      // Act: Directly sync outbox (network is operational)
      final res = await outboxRepo.syncUserOutbox(
        userId: 'user_a',
        supabaseService: supabaseService,
      );

      // Assert: Both API calls executed
      expect(res.synced, 2);
      expect(supabaseService.addFavoriteCalls.length, 1);
      expect(supabaseService.addFavoriteCalls.first['bookId'], '9785555');

      expect(supabaseService.removeFavoriteCalls.length, 1);
      expect(supabaseService.removeFavoriteCalls.first['bookId'], '9786666');

      // Assert: Outbox is cleared
      expect(outboxRepo.getPendingItems('user_a'), isEmpty);
    });
  });

  group('5. Retry, Exponential Backoff & Permanent Failure Policy', () {
    test('Geçici ağ hatalarında retryCount artar ve exponential backoff uygulanır', () async {
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '9787777',
        action: OutboxAction.add,
        bookTitle: 'Backoff Test Book',
        bookAuthor: 'Author',
        bookImageUrl: null,
      );

      supabaseService.errorToAdd = const SocketException('Connection timeout');

      // First sync attempt
      final res1 = await outboxRepo.syncUserOutbox(
        userId: 'user_a',
        supabaseService: supabaseService,
      );
      expect(res1.failed, 1);

      final item1 = outboxRepo.getItem('user_a', '9787777');
      expect(item1?.retryCount, 1);
      expect(item1?.status, OutboxStatus.failed);
      expect(item1?.nextAttemptAt, isNotNull);
      // Backoff delay for retry 1: (1 << 1) = 2 seconds
      expect(item1!.nextAttemptAt!.isAfter(DateTime.now().add(const Duration(milliseconds: 500))), isTrue);

      // Second sync attempt without forceRetry: Should be skipped because backoff period is not reached
      final res2 = await outboxRepo.syncUserOutbox(
        userId: 'user_a',
        supabaseService: supabaseService,
        forceRetry: false,
      );
      expect(res2.skipped, 1);
      expect(res2.failed, 0);

      // Third sync attempt with forceRetry: forces retry even within backoff
      final res3 = await outboxRepo.syncUserOutbox(
        userId: 'user_a',
        supabaseService: supabaseService,
        forceRetry: true,
      );
      expect(res3.failed, 1);
      final item3 = outboxRepo.getItem('user_a', '9787777');
      expect(item3?.retryCount, 2);
    });

    test('5 başarısız denemeden sonra işlem permanentFailure olarak işaretlenir', () async {
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '9788888',
        action: OutboxAction.add,
        bookTitle: 'Permanent Fail Book',
        bookAuthor: 'Author',
        bookImageUrl: null,
      );

      supabaseService.errorToAdd = const SocketException('Continuous network blackout');

      for (int i = 0; i < 5; i++) {
        await outboxRepo.syncUserOutbox(
          userId: 'user_a',
          supabaseService: supabaseService,
          forceRetry: true,
        );
      }

      final item = outboxRepo.getItem('user_a', '9788888');
      expect(item?.retryCount, 5);
      expect(item?.status, OutboxStatus.permanentFailure);

      // Regular sync should now skip permanent failure
      final resSkip = await outboxRepo.syncUserOutbox(
        userId: 'user_a',
        supabaseService: supabaseService,
        forceRetry: false,
      );
      expect(resSkip.skipped, 1);
    });

    test('401/403 kimlik yetki hatalarında döngü sonlanır ve sonsuz tekrar engellenir', () async {
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '9789999',
        action: OutboxAction.add,
        bookTitle: 'Auth Fail Book',
        bookAuthor: 'Author',
        bookImageUrl: null,
      );

      supabaseService.simulateAuth401Error = true;

      final res = await outboxRepo.syncUserOutbox(
        userId: 'user_a',
        supabaseService: supabaseService,
      );

      expect(res.failed, 1);
      final item = outboxRepo.getItem('user_a', '9789999');
      // Auth errors immediately marked as permanentFailure without retrying 5 times
      expect(item?.status, OutboxStatus.permanentFailure);
      expect(item?.lastError?.contains('401'), isTrue);
    });
  });

  group('6. Lost Response & Duplicate Execution Safety (Idempotency)', () {
    test('Sunucu yanıtı kaybolduğunda tekrar denenen istek veritabanını bozmaz', () async {
      final provider = FavoritesProvider(supabaseService, outboxRepo);
      provider.loadFavorites('user_a');

      final book = createTestBook(isbn: '978-IDEMP-1', title: 'Idempotency Book');

      // Network drops after DB record created
      supabaseService.simulateLostResponseOnAdd = true;

      // Initial add -> saved in outbox due to network drop
      await provider.toggleFavorite(userId: 'user_a', book: book);
      expect(provider.hasPendingSync('978-IDEMP-1'), isTrue);
      expect(supabaseService._mockDb.length, 1);

      // Now network returns to normal, retry sync executes
      supabaseService.simulateLostResponseOnAdd = false;
      await provider.retryFailedSync('user_a');

      // Assert: upsert is safe; mock DB contains exactly one entry for this book
      final records = supabaseService._mockDb
          .where((m) => m['book_id'] == '978-IDEMP-1' && m['user_id'] == 'user_a')
          .toList();
      expect(records.length, 1);
      expect(provider.pendingSyncCount, 0);

      provider.dispose();
    });
  });

  group('7. User & Session Isolation', () {
    test('Kullanıcı A kuyruğu Kullanıcı B oturumunda gönderilmez ve silinmez', () async {
      // User A creates 2 pending items
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '978-USERA-1',
        action: OutboxAction.add,
        bookTitle: 'User A Book 1',
        bookAuthor: 'Author A',
        bookImageUrl: null,
      );
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '978-USERA-2',
        action: OutboxAction.add,
        bookTitle: 'User A Book 2',
        bookAuthor: 'Author A',
        bookImageUrl: null,
      );

      // Simulate offline while User A enqueues items
      supabaseService.errorToAdd = const SocketException('Offline');
      final provider = FavoritesProvider(supabaseService, outboxRepo);
      provider.loadFavorites('user_a');
      expect(provider.pendingSyncCount, 2);

      // Wait for any background quiet sync attempt for User A to finish
      await Future.delayed(const Duration(milliseconds: 20));

      // User A logs out
      provider.clearFavorites();
      expect(provider.favorites, isEmpty);

      // Network restores, User B logs in and runs sync
      supabaseService.errorToAdd = null;
      supabaseService.addFavoriteCalls.clear();

      provider.loadFavorites('user_b');
      await provider.retryFailedSync('user_b');

      // Verify no API calls made for User A's books under User B's sync
      expect(supabaseService.addFavoriteCalls.any((c) => c['userId'] == 'user_b'), isFalse);
      expect(supabaseService.addFavoriteCalls.any((c) => c['userId'] == 'user_a'), isFalse);

      // Verify User A's outbox items remain safely in Hive
      final userAItems = outboxRepo.getPendingItems('user_a');
      expect(userAItems.length, 2);
      expect(userAItems.first.isbn13, '978-USERA-1');

      // User A logs back in -> items are restored
      provider.loadFavorites('user_a');
      expect(provider.pendingSyncCount, 2);
      expect(provider.isFavorite('978-USERA-1'), isTrue);

      provider.dispose();
    });
  });

  group('8. Concurrent Taps & Duplicate ISBN Protection', () {
    test('Aynı kitaba eşzamanlı basıldığında tekilleştirme yarış durumunu engeller', () async {
      final provider = FavoritesProvider(supabaseService, outboxRepo);
      provider.loadFavorites('user_a');

      final book = createTestBook(isbn: '978-CONCUR-1', title: 'Concurrent Book');

      // Simultaneous calls
      final f1 = provider.toggleFavorite(userId: 'user_a', book: book);
      final f2 = provider.toggleFavorite(userId: 'user_a', book: book);

      await Future.wait([f1, f2]);

      expect(supabaseService.addFavoriteCalls.length, 1);
      expect(provider.isFavorite('978-CONCUR-1'), isTrue);

      provider.dispose();
    });
  });

  group('9. Process Termination & Outbox Durability', () {
    test('İşlem ağ isteğinden önce diske yazılır; çökme durumunda veri kaybolmaz', () async {
      // Simulate crash right when enqueue happens
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '978-DURABLE-1',
        action: OutboxAction.add,
        bookTitle: 'Durable Book',
        bookAuthor: 'Author',
        bookImageUrl: null,
      );

      // Verify stored immediately in box
      expect(fakeBox.containsKey('outbox_user_a_978-DURABLE-1'), isTrue);

      // Create new instance of repo as if app rebooted
      final rebootedRepo = FavoritesOutboxRepository(fakeBox);
      final pending = rebootedRepo.getPendingItems('user_a');
      expect(pending.length, 1);
      expect(pending.first.isbn13, '978-DURABLE-1');
      expect(pending.first.bookTitle, 'Durable Book');
    });
  });

  group('10. User Experience & Widget Tests (FavoritesScreen)', () {
    testWidgets('Senkronizasyon bekleyen işlem olduğunda bilgi banneri ve bulut simgesi gösterilir', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final completer = Completer<void>();
      supabaseService.delaySyncCompleter = completer;

      // Pre-seed 1 pending outbox item
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '978-UI-1',
        action: OutboxAction.add,
        bookTitle: 'Offline Reading Book',
        bookAuthor: 'Arthur Conan Doyle',
        bookImageUrl: null,
      );

      final favoritesProvider = FavoritesProvider(supabaseService, outboxRepo);
      final authProvider = AuthProvider(FakeTestAuthService());
      await authProvider.login(email: 'userA@libris.com', password: 'password123');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<FavoritesProvider>.value(value: favoritesProvider),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ],
          child: const MaterialApp(
            home: FavoritesScreen(),
          ),
        ),
      );

      // Push stream update so initial loading finishes
      supabaseService.pushStreamUpdate();
      await tester.pump();

      // Verify pending sync banner is visible
      expect(find.byKey(const Key('favorites_sync_pending_banner')), findsOneWidget);
      expect(find.text('Offline Reading Book'), findsOneWidget);

      // Verify cloud upload icon on the book tile
      expect(find.byIcon(Icons.cloud_upload_outlined), findsWidgets);

      // Complete sync cleanly
      completer.complete();
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 5));
      authProvider.dispose();
      favoritesProvider.dispose();
    });

    testWidgets('Başarısız senkronizasyon durumunda hata banneri ve tekrar dene butonu gösterilir', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Pre-seed 1 failed outbox item
      final failedItem = FavoriteOutboxItem(
        id: 'user_a_978-UI-FAIL',
        userId: 'user_a',
        isbn13: '978-UI-FAIL',
        action: OutboxAction.add,
        bookTitle: 'Failed Sync Book',
        bookAuthor: 'Author',
        bookImageUrl: null,
        createdAt: DateTime.now(),
        retryCount: 2,
        status: OutboxStatus.failed,
        lastError: 'Network timeout',
      );
      await fakeBox.put('outbox_user_a_978-UI-FAIL', jsonEncode(failedItem.toJson()));

      // Keep network offline initially so item remains failed
      supabaseService.errorToAdd = const SocketException('Offline');

      final favoritesProvider = FavoritesProvider(supabaseService, outboxRepo);
      final authProvider = AuthProvider(FakeTestAuthService());
      await authProvider.login(email: 'userA@libris.com', password: 'password123');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<FavoritesProvider>.value(value: favoritesProvider),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ],
          child: const MaterialApp(
            home: FavoritesScreen(),
          ),
        ),
      );

      // Push stream update so loading finishes
      supabaseService.pushStreamUpdate();
      await tester.pumpAndSettle();

      // Verify failed sync banner and retry button
      expect(find.byKey(const Key('favorites_sync_failed_banner')), findsOneWidget);
      expect(find.byKey(const Key('favorites_retry_sync_button')), findsOneWidget);

      // Now restore network connection and tap retry button
      supabaseService.errorToAdd = null;
      supabaseService.addFavoriteCalls.clear();
      await tester.tap(find.byKey(const Key('favorites_retry_sync_button')));
      supabaseService.pushStreamUpdate();
      await tester.pumpAndSettle();

      // Verify sync was executed and item was successfully synced
      expect(supabaseService.addFavoriteCalls.length, 1);
      expect(supabaseService.addFavoriteCalls.first['bookId'], '978-UI-FAIL');
      expect(find.byKey(const Key('favorites_sync_failed_banner')), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      authProvider.dispose();
      favoritesProvider.dispose();
    });
  });

  group('11. Advanced Reliability Closure Audit Tests', () {
    test('Sunucuda zaten kayıtlı olan kitapta add -> remove dizisi net sonuç olarak remove üretir', () async {
      // Arrange: Book already exists on the server
      final serverFav = {
        'id': 'fav_srv_1',
        'user_id': 'user_a',
        'book_id': '978-SRV-100',
        'book_title': 'Pre-existing Server Book',
        'book_author': 'Author S',
        'book_image_url': '',
        'added_at': '2024-01-01T00:00:00.000Z',
      };
      await fakeBox.put('favorites_cache_user_a', jsonEncode([serverFav]));

      // Suppose outbox had an add entry (e.g. client had queued add while offline)
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '978-SRV-100',
        action: OutboxAction.add,
        bookTitle: 'Pre-existing Server Book',
        bookAuthor: 'Author S',
        bookImageUrl: '',
      );
      expect(outboxRepo.getItem('user_a', '978-SRV-100')?.action, OutboxAction.add);

      // Act: User toggles to remove
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: '978-SRV-100',
        action: OutboxAction.remove,
        bookTitle: 'Pre-existing Server Book',
        bookAuthor: 'Author S',
        bookImageUrl: '',
      );

      // Assert: Coalescing does NOT cancel out to zero!
      // Because book was on server, desired net result is REMOVE
      final item = outboxRepo.getItem('user_a', '978-SRV-100');
      expect(item, isNotNull);
      expect(item!.action, OutboxAction.remove);
    });

    test('Syncing durumunda kalan kayıt uygulama açılışında güvenle pending durumuna döner', () async {
      // Arrange: Seed an item that was left in 'syncing' status when the app was killed
      final stuckItem = FavoriteOutboxItem(
        id: 'user_a_978-STUCK-1',
        userId: 'user_a',
        isbn13: '978-STUCK-1',
        action: OutboxAction.add,
        bookTitle: 'Stuck Book',
        bookAuthor: 'Author',
        createdAt: DateTime.now(),
        status: OutboxStatus.syncing, // left syncing
      );
      await fakeBox.put('outbox_user_a_978-STUCK-1', jsonEncode(stuckItem.toJson()));

      // Act: App restarts, new repo reads items
      final freshRepo = FavoritesOutboxRepository(fakeBox);
      final items = freshRepo.getPendingItems('user_a');

      // Assert: The stuck item was recovered to pending
      expect(items.length, 1);
      expect(items.first.status, OutboxStatus.pending);

      final singleItem = freshRepo.getItem('user_a', '978-STUCK-1');
      expect(singleItem?.status, OutboxStatus.pending);
    });

    test('401/403 hatasıyla duran işlem kullanıcı yeniden giriş yapınca pending durumuna döner ve senkronize edilir', () async {
      // Arrange: An item failed permanently due to 401 JWT expiration
      final authFailedItem = FavoriteOutboxItem(
        id: 'user_a_978-AUTH-EXP',
        userId: 'user_a',
        isbn13: '978-AUTH-EXP',
        action: OutboxAction.add,
        bookTitle: 'Auth Expired Book',
        bookAuthor: 'Author',
        createdAt: DateTime.now(),
        status: OutboxStatus.permanentFailure,
        lastError: 'Auth error (401/403): Invalid JWT token',
      );
      await fakeBox.put('outbox_user_a_978-AUTH-EXP', jsonEncode(authFailedItem.toJson()));

      // Pre-condition: item is in permanentFailure
      expect(outboxRepo.getItem('user_a', '978-AUTH-EXP')?.status, OutboxStatus.permanentFailure);

      // Act 1: resetAuthFailures directly recovers it to pending
      outboxRepo.resetAuthFailures('user_a');
      final recovered = outboxRepo.getItem('user_a', '978-AUTH-EXP');
      expect(recovered?.status, OutboxStatus.pending);
      expect(recovered?.retryCount, 0);

      // Act 2: When provider loads favorites for re-authenticated user, quiet sync executes and finishes
      final provider = FavoritesProvider(supabaseService, outboxRepo);
      await provider.loadFavorites('user_a');
      await Future.delayed(const Duration(milliseconds: 20));

      // Assert: Synced to server and outbox cleared
      expect(supabaseService.addFavoriteCalls.any((c) => c['bookId'] == '978-AUTH-EXP'), isTrue);
      expect(outboxRepo.getItem('user_a', '978-AUTH-EXP'), isNull);

      provider.dispose();
    });

    test('Kuyruk kapasitesi (100) aşıldığında permanent/failed kayıtlar önce silinir, pending korunur', () async {
      // Pre-seed 99 pending items
      for (int i = 0; i < 99; i++) {
        final item = FavoriteOutboxItem(
          id: 'user_a_isbn_$i',
          userId: 'user_a',
          isbn13: 'isbn_$i',
          action: OutboxAction.add,
          bookTitle: 'Book $i',
          bookAuthor: 'Author',
          createdAt: DateTime.now().subtract(Duration(minutes: 100 - i)),
          status: OutboxStatus.pending,
        );
        await fakeBox.put('outbox_user_a_isbn_$i', jsonEncode(item.toJson()));
      }

      // Add 1 permanentFailure item
      final permFail = FavoriteOutboxItem(
        id: 'user_a_isbn_fail',
        userId: 'user_a',
        isbn13: 'isbn_fail',
        action: OutboxAction.add,
        bookTitle: 'Failed Book',
        bookAuthor: 'Author',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        status: OutboxStatus.permanentFailure,
        lastError: 'Permanent validation rejection',
      );
      await fakeBox.put('outbox_user_a_isbn_fail', jsonEncode(permFail.toJson()));

      // Total count is now 100 (capacity limit)
      expect(outboxRepo.getPendingItems('user_a').length, 100);

      // Act: Enqueue a brand new 101st item
      await outboxRepo.enqueue(
        userId: 'user_a',
        isbn13: 'isbn_new_101',
        action: OutboxAction.add,
        bookTitle: 'New 101st Book',
        bookAuthor: 'Author',
        bookImageUrl: null,
      );

      // Assert: The permanent failure item was evicted first to protect active pending user edits!
      expect(outboxRepo.getItem('user_a', 'isbn_fail'), isNull);
      expect(outboxRepo.getItem('user_a', 'isbn_new_101'), isNotNull);
      // Oldest pending items (e.g. isbn_0) was preserved
      expect(outboxRepo.getItem('user_a', 'isbn_0'), isNotNull);
    });
  });
}
