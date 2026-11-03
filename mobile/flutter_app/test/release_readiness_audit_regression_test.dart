import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/data/models/book_dto.dart';
import 'package:book_ai_app/data/repositories/interactions_outbox_repository.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:book_ai_app/services/auth_service_base.dart';
import 'package:book_ai_app/application/use_cases/manage_recommendations_use_case.dart';
import 'package:book_ai_app/application/use_cases/manage_catalog_use_case.dart';
import 'package:book_ai_app/application/use_cases/view_book_details_use_case.dart';
import 'package:book_ai_app/providers/auth_provider.dart' as app_auth;
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/providers/catalog_provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/providers/theme_provider.dart';
import 'package:book_ai_app/screens/settings_screen.dart';
import 'package:book_ai_app/screens/detail_screen.dart';

import 'book_detail_bottom_sheet_test.dart' show DetailTestSupabaseService;


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

class FakeHttpAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  FakeHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class AuditFakeAuthService implements AuthServiceBase {
  User? _currentUser;
  final _ctrl = StreamController<AuthState>.broadcast();

  AuditFakeAuthService([this._currentUser]);

  void setUser(String id, String email) {
    _currentUser = User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-27T10:00:00Z',
      email: email,
    );
    _ctrl.add(AuthState(AuthChangeEvent.signedIn, Session(
      accessToken: 'dummy_token',
      tokenType: 'bearer',
      user: _currentUser!,
    )));
  }

  @override
  User? get currentUser => _currentUser;

  @override
  bool get isConfigured => true;

  @override
  Stream<AuthState> get authStateStream => _ctrl.stream;

  @override
  Future<AuthResponse> signIn({required String email, required String password}) async {
    setUser('uid_1', email);
    return AuthResponse(
      user: _currentUser,
      session: Session(accessToken: 'token', tokenType: 'bearer', user: _currentUser!),
    );
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _ctrl.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuditBookRepository implements BookRepository {
  final Book sample;
  AuditBookRepository(this.sample);

  @override
  Future<Book?> getBookByIsbn(String isbn) async => sample;

  @override
  Future<List<Book>> getRecommendations(String title) async => [];

  @override
  Future<String?> getUserInteraction(String userId, String bookId) async => null;

  @override
  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async => true;

  @override
  Future<bool> trackActivity({
    required String userId,
    required String activityType,
    required String bookId,
    String? bookName,
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRecommendationsUseCase implements ManageRecommendationsUseCase {
  final bool Function(String interaction)? onFeedback;
  FakeRecommendationsUseCase({this.onFeedback});

  @override
  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    if (onFeedback != null) {
      return onFeedback!(interaction);
    }
    return true;
  }

  @override
  Future<List<Book>> getPersonalizedRecs(String userId, List<Book> popularBooks, {String? category, bool? excludeCompleted}) async => [];

  @override
  Future<bool> submitOnboarding({
    required String userId,
    required List<String> bookIds,
    required List<String> genres,
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCatalogUseCase implements ManageCatalogUseCase {
  final List<Map<String, dynamic>> categoriesToReturn;
  FakeCatalogUseCase({required this.categoriesToReturn});

  @override
  Future<List<Map<String, dynamic>>> getCategories() async => categoriesToReturn;

  @override
  List<Book> getCachedPopularBooks() => [];

  @override
  Future<int> getTotalBookCount() async => 100;

  @override
  Future<List<Book>> getPopularBooks({bool forceRefresh = false, int limit = 2000}) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBox intBox;
  late InteractionsOutboxRepository intRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    intBox = FakeBox();
    intRepo = InteractionsOutboxRepository(intBox);
  });

  tearDown(() {
    intBox.clear();
  });

  group('Cross-Client Contract & DTO Resilience', () {
    test('FavoriteBookDto.fromJson supports cross-client fields with fallbacks', () {
      // 1. Backend / Web format: isbn13, title, thumbnail
      final webFormat = {
        'id': 'fav-123',
        'user_id': 'user-1',
        'isbn13': '9780441013593',
        'title': 'Dune',
        'thumbnail': 'https://example.com/dune.jpg',
        'added_at': '2026-10-27T10:00:00Z',
      };
      final dtoFromWeb = FavoriteBookDto.fromJson(webFormat);
      expect(dtoFromWeb.isbn13, '9780441013593');
      expect(dtoFromWeb.bookTitle, 'Dune');
      expect(dtoFromWeb.thumbnail, 'https://example.com/dune.jpg');

      // 2. Supabase table format: book_id, book_title, book_image_url
      final supabaseFormat = {
        'id': 'fav-456',
        'user_id': 'user-2',
        'book_id': '9780452284234',
        'book_title': '1984',
        'book_image_url': 'https://example.com/1984.jpg',
        'added_at': '2026-10-27T11:00:00Z',
      };
      final dtoFromSb = FavoriteBookDto.fromJson(supabaseFormat);
      expect(dtoFromSb.isbn13, '9780452284234');
      expect(dtoFromSb.bookTitle, '1984');
      expect(dtoFromSb.thumbnail, 'https://example.com/1984.jpg');
    });

    test('CatalogProvider.fetchGenres safely parses numeric, string, or missing count without crashing', () async {
      final fakeUseCase = FakeCatalogUseCase(categoriesToReturn: [
        {'name': 'Fiction', 'count': 420}, // integer
        {'name': 'Sci-Fi', 'count': 150.0}, // double / num
        {'name': 'Classics', 'count': null}, // null count
      ]);

      final provider = CatalogProvider(manageCatalog: fakeUseCase);
      await provider.fetchGenres();

      expect(provider.defaultGenres.contains('Fiction'), isTrue);
      expect(provider.defaultGenres.contains('Sci-Fi'), isTrue);
      expect(provider.defaultGenres.contains('Classics'), isTrue);
      expect(provider.categoryCounts['Fiction'], 420);
      expect(provider.categoryCounts['Sci-Fi'], 150);
      expect(provider.categoryCounts['Classics'], 0);
    });
  });

  group('ApiService Feedback Error Propagation & Outbox Discrimination', () {
    test('ApiService.submitFeedback propagates DioException on 400 Bad Request without swallowing', () async {
      final apiService = ApiService.instance;
      apiService.init();
      apiService.testDio.httpClientAdapter = FakeHttpAdapter((opts) {
        return ResponseBody.fromString(
          jsonEncode({'error': 'Invalid interaction: foo'}),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      expect(
        () => apiService.submitFeedback(
          userId: 'test_user',
          bookId: '9780000000001',
          interaction: 'foo',
        ),
        throwsA(isA<DioException>()),
      );
    });

    test('RecommendationProvider does NOT enqueue to outbox on 4xx Bad Request server rejection', () async {
      final useCase = FakeRecommendationsUseCase(
        onFeedback: (_) => throw Exception('400 Bad Request: Invalid interaction'),
      );
      final provider = RecommendationProvider(
        manageRecommendations: useCase,
        outboxRepo: intRepo,
      );

      final success = await provider.submitFeedback(
        userId: 'user_test_4xx',
        bookId: '9780000000001',
        interaction: 'invalid_type',
      );

      expect(success, isFalse);
      expect(provider.hasPendingInteraction('user_test_4xx', '9780000000001'), isFalse);
    });

    test('RecommendationProvider enqueues to outbox on transient network failure and returns true', () async {
      final useCase = FakeRecommendationsUseCase(
        onFeedback: (_) => throw Exception('SocketException: Failed host lookup'),
      );
      final provider = RecommendationProvider(
        manageRecommendations: useCase,
        outboxRepo: intRepo,
      );

      final success = await provider.submitFeedback(
        userId: 'user_test_offline',
        bookId: '9780000000002',
        interaction: 'want_to_read',
      );

      // Preserved in durable outbox for subsequent sync
      expect(success, isTrue);
      expect(provider.hasPendingInteraction('user_test_offline', '9780000000002'), isTrue);
    });
  });

  group('DetailScreen Offline Desired-State & Interaction Race Protection', () {
    const sampleBook = Book(
      isbn13: '9780000000003',
      title: 'Brave New World',
      authors: 'Aldous Huxley',
      categories: 'Fiction',
      thumbnail: '',
      description: 'Dystopian classic.',
      publishedDate: '1932',
      averageRating: 4.5,
      ratingsCount: 1200,
      pageCount: 268,
    );

    testWidgets('DetailScreen immediately renders pending offline interaction from outbox', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = AuditFakeAuthService();
      fakeAuth.setUser('test_reader', 'reader@libris.app');

      final fakeRepo = AuditBookRepository(sampleBook);
      final fakeSupabase = DetailTestSupabaseService();
      final recProvider = RecommendationProvider(
        manageRecommendations: ManageRecommendationsUseCase(fakeRepo),
        outboxRepo: intRepo,
      );

      // Enqueue offline interaction in durable outbox
      await intRepo.enqueue(
        userId: 'test_reader',
        isbn13: '9780000000003',
        interaction: 'reading',
      );

      final langProvider = LanguageProvider();
      langProvider.setTranslationsForTest('en', {
        'currently_reading': 'Currently Reading',
        'sign_in_hint': 'Sign in to sync your library',
        'sign_in_subtitle': 'Access your bookmarks across devices',
        'logout': 'Sign Out',
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => app_auth.AuthProvider(fakeAuth)),
            ChangeNotifierProvider(create: (_) => FavoritesProvider(fakeSupabase)),
            ChangeNotifierProvider.value(value: langProvider),
            ChangeNotifierProvider.value(value: recProvider),
            Provider<BookRepository>(create: (_) => fakeRepo),
            Provider<ViewBookDetailsUseCase>(create: (_) => ViewBookDetailsUseCase(fakeRepo)),
            Provider<ManageRecommendationsUseCase>(create: (_) => ManageRecommendationsUseCase(fakeRepo)),
          ],
          child: const MaterialApp(
            home: DetailScreen(
              isbn: '_',
              initialBook: sampleBook,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Active status badge should reflect 'reading' from pending outbox
      expect(find.text(langProvider.translate('currently_reading')), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('SettingsScreen Guest vs Authenticated User Experience', () {
    testWidgets('SettingsScreen shows Sign In tile when user is logged out (no ghost user or logout)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeAuth = AuditFakeAuthService(); // unauthenticated (currentUser == null)
      final fakeSupabase = DetailTestSupabaseService();
      final langProvider = LanguageProvider();
      langProvider.setTranslationsForTest('en', {
        'currently_reading': 'Currently Reading',
        'sign_in_hint': 'Sign in to sync your library',
        'sign_in_subtitle': 'Access your bookmarks across devices',
        'logout': 'Sign Out',
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => app_auth.AuthProvider(fakeAuth)),
            ChangeNotifierProvider(create: (_) => FavoritesProvider(fakeSupabase)),
            ChangeNotifierProvider.value(value: langProvider),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Guest user must see Sign In option
      expect(find.text(langProvider.translate('sign_in_hint')), findsOneWidget);
      // Ghost User or Logout must NOT be shown
      expect(find.text(langProvider.translate('logout')), findsNothing);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('SettingsScreen shows user profile & logout when authenticated', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeAuth = AuditFakeAuthService();
      fakeAuth.setUser('uid_reader', 'reader@libris.app');
      final fakeSupabase = DetailTestSupabaseService();
      final langProvider = LanguageProvider();
      langProvider.setTranslationsForTest('en', {
        'currently_reading': 'Currently Reading',
        'sign_in_hint': 'Sign in to sync your library',
        'sign_in_subtitle': 'Access your bookmarks across devices',
        'logout': 'Sign Out',
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => app_auth.AuthProvider(fakeAuth)),
            ChangeNotifierProvider(create: (_) => FavoritesProvider(fakeSupabase)),
            ChangeNotifierProvider.value(value: langProvider),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('reader@libris.app'), findsOneWidget);
      expect(find.text(langProvider.translate('logout')), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });
  });
}
