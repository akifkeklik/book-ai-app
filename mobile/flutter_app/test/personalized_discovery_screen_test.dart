import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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

class DiscoveryTestBookRepository implements BookRepository {
  final List<Book> recsToReturn;
  final bool throwError;
  final List<String> submittedFeedback = [];

  DiscoveryTestBookRepository({
    this.recsToReturn = const [],
    this.throwError = false,
  });

  @override
  Future<List<Book>> getPersonalizedRecommendations(String userId) async {
    if (throwError) throw Exception('Recommendation engine failure');
    return recsToReturn;
  }

  @override
  Future<List<Book>> getFallbackRecommendations(String userId) async {
    if (throwError) throw Exception('Fallback recommendations failure');
    return recsToReturn;
  }

  @override
  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    submittedFeedback.add('$userId:$bookId:$interaction');
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

class DiscoveryFakeAuthService implements AuthServiceBase {
  final User? _user;
  DiscoveryFakeAuthService([this._user]);

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => _user;

  @override
  Stream<AuthState> get authStateStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class DiscoveryTestSupabaseService implements SupabaseService {
  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) {
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const sampleUser = User(
    id: 'test-user-42',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );

  const sampleFavRec = Book(
    isbn13: '9780141036144',
    title: 'Nineteen Eighty-Four',
    authors: 'George Orwell',
    categories: 'Fiction',
    thumbnail: '',
    description: 'Dystopian classic.',
    publishedDate: '1949',
    averageRating: 4.8,
    ratingsCount: 1200,
    pageCount: 328,
    recommendationReason: "Because you favorited 'Animal Farm'",
  );

  const sampleReadingRec = Book(
    isbn13: '9780441013593',
    title: 'Dune Messiah',
    authors: 'Frank Herbert',
    categories: 'Science Fiction',
    thumbnail: '',
    description: 'Sci-fi epic sequel.',
    publishedDate: '1969',
    averageRating: 4.6,
    ratingsCount: 800,
    pageCount: 256,
    recommendationReason: "Because you're reading 'Dune'",
  );

  const sampleTasteRec = Book(
    isbn13: '9780345391803',
    title: 'The Hitchhiker\'s Guide to the Galaxy',
    authors: 'Douglas Adams',
    categories: 'Science Fiction, Comedy',
    thumbnail: '',
    description: 'Comedy sci-fi.',
    publishedDate: '1979',
    averageRating: 4.7,
    ratingsCount: 2500,
    pageCount: 224,
    recommendationReason: 'Because you enjoy Science Fiction',
  );

  Widget createDiscoveryWidget({
    required DiscoveryTestBookRepository repo,
    bool loggedIn = true,
  }) {
    final fakeAuthService = DiscoveryFakeAuthService(loggedIn ? sampleUser : null);
    final fakeSupabase = DiscoveryTestSupabaseService();
    final authProv = app_auth.AuthProvider(fakeAuthService);

    final manageRecs = ManageRecommendationsUseCase(repo);
    final recProvider = RecommendationProvider(manageRecommendations: manageRecs);
    final catalogUseCase = ManageCatalogUseCase(repo);
    final catalogProvider = CatalogProvider(manageCatalog: catalogUseCase);

    final langProvider = LanguageProvider();
    langProvider.setTranslationsForTest('en', {
      'personalized_discovery_title': 'Personalized Discovery',
      'personalized_discovery_subtitle': 'Curated literature shaped by your unique reading journey',
      'filter_all': 'All',
      'filter_favorites': 'From Favorites',
      'filter_reading': 'Reading Journey',
      'filter_taste': 'Taste & Genres',
      'dismiss_recommendation': 'Not Interested',
      'recommendation_dismissed': 'Book removed from recommendations',
      'empty_personalized_title': 'No recommendations found',
      'empty_personalized_desc': 'Save books to your favorites or reading list to train your personal discovery engine.',
      'explore_catalog_cta': 'Explore Catalog',
      'reset_filters': 'Reset Filters',
      'active_recommendations_count': '{count} books recommended',
      'unfavorite': 'Remove from Favorites',
      'add_to_favorites': 'Add to Favorites',
      'manage_shelf': 'Manage Shelf',
      'reading': 'Reading',
      'want_to_read': 'Want to Read',
      'finished': 'Finished',
      'retry': 'Retry',
      'error_loading_books': 'Failed to load recommendations',
      'reason_favorited': "Because you favorited '{title}'",
      'reason_currently_reading': "Because you're reading '{title}'",
      'reason_enjoy_genre': 'Because you enjoy {genre}',
      'login_required_personalized_title': 'Sign In for Personalized Learning',
      'login_required_personalized_desc': 'Sign in to access your reading journey, track your books, and receive tailor-made recommendations.',
      'sign_in_to_continue': 'Sign In to Continue',
    });

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<app_auth.AuthProvider>.value(value: authProv),
        ChangeNotifierProvider<FavoritesProvider>(create: (_) => FavoritesProvider(fakeSupabase)),
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
        ChangeNotifierProvider<LanguageProvider>.value(value: langProvider),
        ChangeNotifierProvider<RecommendationProvider>.value(value: recProvider),
      ],
      child: const MaterialApp(
        home: PersonalizedDiscoveryScreen(),
      ),
    );
  }

  group('PersonalizedDiscoveryScreen End-to-End Suite', () {
    testWidgets('renders all personalized recommendations with localized reasoning pills', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = DiscoveryTestBookRepository(recsToReturn: [sampleFavRec, sampleReadingRec, sampleTasteRec]);
      await tester.pumpWidget(createDiscoveryWidget(repo: repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Screen Title
      expect(find.text('Personalized Discovery'), findsOneWidget);

      // Verify all 3 books render
      expect(find.text('Nineteen Eighty-Four'), findsOneWidget);
      expect(find.text('Dune Messiah'), findsOneWidget);
      expect(find.text('The Hitchhiker\'s Guide to the Galaxy'), findsOneWidget);

      // Verify Rationale pills
      expect(find.text("Because you favorited 'Animal Farm'"), findsOneWidget);
      expect(find.text("Because you're reading 'Dune'"), findsOneWidget);
      expect(find.text('Because you enjoy Science Fiction'), findsOneWidget);
    });

    testWidgets('filter chips filter recommendations dynamically by rationale source', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = DiscoveryTestBookRepository(recsToReturn: [sampleFavRec, sampleReadingRec, sampleTasteRec]);
      await tester.pumpWidget(createDiscoveryWidget(repo: repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Filter by "From Favorites"
      await tester.tap(find.text('From Favorites (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Nineteen Eighty-Four'), findsOneWidget);
      expect(find.text('Dune Messiah'), findsNothing);
      expect(find.text('The Hitchhiker\'s Guide to the Galaxy'), findsNothing);

      // Filter by "Reading Journey"
      await tester.tap(find.text('Reading Journey (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Nineteen Eighty-Four'), findsNothing);
      expect(find.text('Dune Messiah'), findsOneWidget);
      expect(find.text('The Hitchhiker\'s Guide to the Galaxy'), findsNothing);

      // Filter by "Taste & Genres"
      await tester.tap(find.text('Taste & Genres (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Nineteen Eighty-Four'), findsNothing);
      expect(find.text('Dune Messiah'), findsNothing);
      expect(find.text('The Hitchhiker\'s Guide to the Galaxy'), findsOneWidget);

      // Reset filter back to All
      await tester.tap(find.text('All (3)'));
      await tester.pumpAndSettle();

      expect(find.text('Nineteen Eighty-Four'), findsOneWidget);
      expect(find.text('Dune Messiah'), findsOneWidget);
      expect(find.text('The Hitchhiker\'s Guide to the Galaxy'), findsOneWidget);
    });

    testWidgets('dismiss action optimistically removes book, invokes dislike feedback, and shows snackbar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = DiscoveryTestBookRepository(recsToReturn: [sampleFavRec, sampleReadingRec]);
      await tester.pumpWidget(createDiscoveryWidget(repo: repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Nineteen Eighty-Four'), findsOneWidget);

      // Find dislike icon buttons (thumbs down)
      final dismissButtons = find.byIcon(Icons.thumb_down_alt_outlined);
      expect(dismissButtons, findsNWidgets(2));

      // Tap dislike on the first book (Nineteen Eighty-Four)
      await tester.tap(dismissButtons.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify feedback submitted to repository
      expect(repo.submittedFeedback, contains('test-user-42:9780141036144:dislike'));

      // Verify snackbar is displayed
      expect(find.text('Book removed from recommendations'), findsOneWidget);

      // Verify book was removed optimistically
      expect(find.text('Nineteen Eighty-Four'), findsNothing);
      expect(find.text('Dune Messiah'), findsOneWidget);
    });

    testWidgets('empty state renders illustrated view and Explore Catalog CTA when no recs available', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = DiscoveryTestBookRepository(recsToReturn: []);
      await tester.pumpWidget(createDiscoveryWidget(repo: repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No recommendations found'), findsOneWidget);
      expect(find.text('Explore Catalog'), findsOneWidget);
    });

    testWidgets('error state renders error message and Retry button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = DiscoveryTestBookRepository(throwError: true);
      await tester.pumpWidget(createDiscoveryWidget(repo: repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Failed to load recommendations'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
 
    testWidgets('unauthenticated state renders Sign In prompt and Explore Catalog CTA when user is not logged in', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = DiscoveryTestBookRepository(recsToReturn: []);
      await tester.pumpWidget(createDiscoveryWidget(repo: repo, loggedIn: false));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('Sign In for Personalized Learning'), findsOneWidget);
      expect(find.text('Sign In to Continue'), findsOneWidget);
      expect(find.text('Explore Catalog'), findsOneWidget);
    });
  });
}