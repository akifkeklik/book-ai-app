import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/screens/detail_screen.dart';
import 'package:book_ai_app/providers/auth_provider.dart' as app_auth;
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/application/use_cases/view_book_details_use_case.dart';
import 'package:book_ai_app/application/use_cases/manage_recommendations_use_case.dart';
import 'package:book_ai_app/services/supabase_service.dart';

import 'auth_provider_test.dart' show FakeAuthService;

class DetailTestBookRepository implements BookRepository {
  final Book sample;
  final bool throwOnFetch;
  DetailTestBookRepository(this.sample, {this.throwOnFetch = false});

  @override
  Future<Book?> getBookByIsbn(String isbn) async {
    if (throwOnFetch) throw Exception('Network timeout / connection error');
    return sample;
  }

  @override
  Future<List<Book>> getRecommendations(String title) async => [];

  @override
  Future<String?> getUserInteraction(String userId, String bookId) async => null;

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

class DetailTestSupabaseService implements SupabaseService {
  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) {
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const sampleBook = Book(
    isbn13: '_',
    title: '1984',
    authors: 'George Orwell',
    categories: 'Fiction',
    thumbnail: '',
    description: 'A classic dystopian novel.',
    publishedDate: '1949',
    averageRating: 4.8,
    ratingsCount: 5000,
    pageCount: 328,
  );

  Widget createDetailWidget({required Book book, bool throwOnFetch = false}) {
    final fakeRepo = DetailTestBookRepository(book, throwOnFetch: throwOnFetch);
    final fakeAuthService = FakeAuthService();
    final fakeSupabase = DetailTestSupabaseService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider(fakeAuthService)),
        ChangeNotifierProvider(create: (_) => FavoritesProvider(fakeSupabase)),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => RecommendationProvider(manageRecommendations: ManageRecommendationsUseCase(fakeRepo))),
        Provider<ViewBookDetailsUseCase>(create: (_) => ViewBookDetailsUseCase(fakeRepo)),
        Provider<ManageRecommendationsUseCase>(create: (_) => ManageRecommendationsUseCase(fakeRepo)),
      ],
      child: MaterialApp(
        home: DetailScreen(
          isbn: book.isbn13,
          initialBook: book,
        ),
      ),
    );
  }

  group('DetailScreen Dynamic Ambiance & Library Bottom Sheet', () {
    testWidgets('renders bottom action bar with manage library and quick favorite', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createDetailWidget(book: sampleBook));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1984'), findsWidgets);
      expect(find.byIcon(Icons.bookmark_outline_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('tapping manage in library opens modal bottom sheet with status options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createDetailWidget(book: sampleBook));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap "Manage in Library" button
      await tester.tap(find.byIcon(Icons.bookmark_outline_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modal bottom sheet should be visible with status choices
      expect(find.byIcon(Icons.auto_stories_rounded), findsWidgets); // Reading
      expect(find.byIcon(Icons.bookmark_add_rounded), findsWidgets); // Want to read
      expect(find.byIcon(Icons.check_circle_rounded), findsWidgets); // Finished

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('initialBook remains rendered and is not replaced by error screen when background fetch fails', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const realIsbnBook = Book(
        isbn13: '9780007111503',
        title: 'Partners in Crime',
        authors: 'Agatha Christie',
        categories: 'Mystery & Thriller',
        thumbnail: '',
        description: 'Classic detective stories.',
        publishedDate: '1929',
        averageRating: 4.5,
        ratingsCount: 1200,
        pageCount: 250,
      );

      // Render with throwOnFetch=true
      await tester.pumpWidget(createDetailWidget(book: realIsbnBook, throwOnFetch: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Book title and details MUST remain visible despite background fetch failure
      expect(find.text('Partners in Crime'), findsWidgets);
      expect(find.text('Agatha Christie'), findsWidgets);
      // Retry button / error screen should NOT be shown because initialBook is already present
      expect(find.byIcon(Icons.refresh), findsNothing);

      await tester.pump(const Duration(seconds: 5));
    });
  });
}
