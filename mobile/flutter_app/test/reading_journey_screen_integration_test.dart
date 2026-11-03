import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/screens/personalized_discovery_screen.dart';
import 'package:book_ai_app/providers/auth_provider.dart' as app_auth;
import 'package:book_ai_app/providers/catalog_provider.dart';
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/application/use_cases/manage_catalog_use_case.dart';
import 'package:book_ai_app/application/use_cases/manage_recommendations_use_case.dart';
import 'package:book_ai_app/services/auth_service_base.dart';
import 'package:book_ai_app/services/supabase_service.dart';

class MockBookRepo implements BookRepository {
  final List<Book> books;
  final List<String> submittedInteractions = [];

  MockBookRepo({required this.books});

  @override
  Future<List<Book>> getPersonalizedRecommendations(String userId) async => books;

  @override
  Future<List<Book>> getFallbackRecommendations(String userId) async => books;

  @override
  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    submittedInteractions.add('$userId:$bookId:$interaction');
    return true;
  }

  @override
  Future<List<Book>> getPopularBooks({int limit = 20}) async => [];

  @override
  List<Book> getCachedPopularBooks() => [];

  @override
  void savePopularBooksToCache(List<Book> books) {}

  Future<List<String>> getGenres() async => ['Fiction', 'Science Fiction'];

  @override
  Future<int> getTotalBookCount() async => 42;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthService implements AuthServiceBase {
  final User? _user;
  MockAuthService(this._user);

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => _user;

  @override
  Stream<AuthState> get authStateStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockSupabaseService implements SupabaseService {
  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const sampleUser = User(
    id: 'user-journey-test-123',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );

  const bookA = Book(
    isbn13: '9780141036144',
    title: 'Nineteen Eighty-Four',
    authors: 'George Orwell',
    categories: 'Classics, Dystopian',
    description: 'A masterpiece',
    thumbnail: '',
    averageRating: 4.7,
    ratingsCount: 95000,
    publishedDate: '1949',
    pageCount: 328,
    recommendationReason: "Because you favorited 'Animal Farm'",
  );

  const bookB = Book(
    isbn13: '9780441013593',
    title: 'Dune Messiah',
    authors: 'Frank Herbert',
    categories: 'Science Fiction, Epic',
    description: 'Sequel to Dune',
    thumbnail: '',
    averageRating: 4.4,
    ratingsCount: 34000,
    publishedDate: '1969',
    pageCount: 256,
    recommendationReason: "Because you're reading 'Dune'",
  );

  Widget createWidget({required MockBookRepo repo}) {
    SharedPreferences.setMockInitialValues({});
    final authBase = MockAuthService(sampleUser);
    final supaService = MockSupabaseService();
    final authProv = app_auth.AuthProvider(authBase);
    final catUseCase = ManageCatalogUseCase(repo);
    final recUseCase = ManageRecommendationsUseCase(repo);
    final catProv = CatalogProvider(manageCatalog: catUseCase);
    final recProv = RecommendationProvider(manageRecommendations: recUseCase);

    final langProvider = LanguageProvider();
    langProvider.setTranslationsForTest('en', {
      'personalized_discovery_title': 'Personalized Discovery',
      'personalized_discovery_subtitle': 'Curated literature shaped by your unique reading journey',
      'filter_all': 'All',
      'filter_favorites': 'From Favorites',
      'filter_reading': 'Reading Journey',
      'filter_taste': 'Taste & Genres',
      'reading_journey_title': 'Reading Journey',
      'local_goal_badge': 'Local device goal',
      'goal_books_per_week': '{count} books / week',
      'goal_books_per_year': '{count} books / year',
      'books_progress': '{completed} of {target} books',
      'tab_currently_reading': 'Currently Reading',
      'tab_want_to_read': 'Want to Read',
      'tab_finished': 'Completed',
      'next_book_to_read': 'Your Next Book',
      'start_reading': 'Start Reading',
      'add_to_want_to_read': 'Add to Reading List',
      'status_reading': 'Reading',
      'status_finished': 'Finished',
      'status_want_to_read': 'Want to Read',
      'empty_journey_title': 'Start Your Reading Journey',
      'empty_journey_desc': 'Select your first book from the personalized recommendations below to start tracking your reading.',
      'recommended_for_you': 'Recommended',
      'active_recommendations_count': '{count} books recommended',
      'reset_filters': 'Reset Filters',
      'empty_personalized_title': 'No recommendations found',
      'manage_shelf': 'Manage Shelf',
      'unfavorite': 'Unfavorite',
      'add_to_favorites': 'Add to Favorites',
      'dismiss_recommendation': 'Not Interested',
      'retry': 'Retry',
    });

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<app_auth.AuthProvider>.value(value: authProv),
        ChangeNotifierProvider<LanguageProvider>.value(value: langProvider),
        ChangeNotifierProvider(create: (_) => FavoritesProvider(supaService)),
        ChangeNotifierProvider<CatalogProvider>.value(value: catProv),
        ChangeNotifierProvider<RecommendationProvider>.value(value: recProv),
      ],
      child: const MaterialApp(
        home: PersonalizedDiscoveryScreen(),
      ),
    );
  }

  group('Personalized Learning Journey & Reading Progress Suite', () {
    testWidgets('renders reading journey header, goal badge, and progress bar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = MockBookRepo(books: [bookA, bookB]);
      await tester.pumpWidget(createWidget(repo: repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Verify Reading Journey title & local device badge
      expect(find.text('Reading Journey'), findsOneWidget);
      expect(find.text('Local device goal'), findsOneWidget);

      // 2. Default goal is 1 book / week
      expect(find.text('1 books / week'), findsOneWidget);

      // 3. Progress bar is present
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 4. Milestone tabs are rendered
      expect(find.text('Currently Reading (0)'), findsOneWidget);
      expect(find.text('Want to Read (0)'), findsOneWidget);
      expect(find.text('Completed (0)'), findsOneWidget);
    });

    testWidgets('1-tap quick action on Next Book adds book to reading shelf optimistically', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = MockBookRepo(books: [bookA, bookB]);
      await tester.pumpWidget(createWidget(repo: repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Find "Start Reading" button in Next Book spotlight
      final startReadingBtn = find.text('Start Reading');
      expect(startReadingBtn, findsOneWidget);

      // Tap "Start Reading"
      await tester.tap(startReadingBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify feedback submitted to repository
      expect(
        repo.submittedInteractions,
        contains('user-journey-test-123:9780141036144:reading'),
      );

      // Verify Currently Reading tab counter incremented to 1
      expect(find.text('Currently Reading (1)'), findsOneWidget);
    });
  });
}
