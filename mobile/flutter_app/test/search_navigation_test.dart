import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:book_ai_app/application/use_cases/search_books_use_case.dart';
import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/providers/search_provider.dart';
import 'package:book_ai_app/screens/search_screen.dart';

import 'book_provider_test.dart' show FakeBookRepository;

void main() {
  testWidgets('tapping AI discovery banner on SearchScreen navigates to /ai via GoRouter', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeRepo = FakeBookRepository();
    final searchUseCase = SearchBooksUseCase(fakeRepo);

    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
        GoRoute(
          path: '/ai',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('AI Discovery Screen Route')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SearchProvider(searchBooksUseCase: searchUseCase),
          ),
          ChangeNotifierProvider(
            create: (_) => LanguageProvider(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify SearchScreen is rendered in initial state with AI Discovery Banner
    expect(find.byType(SearchScreen), findsOneWidget);
    final aiBannerFinder = find.byIcon(Icons.auto_awesome);
    expect(aiBannerFinder, findsOneWidget);

    // Tap the AI Discovery banner
    await tester.tap(aiBannerFinder);
    await tester.pumpAndSettle();

    // Verify navigation smoothly transitioned to /ai destination without routing crash
    expect(find.text('AI Discovery Screen Route'), findsOneWidget);
  });

  group('SearchProvider', () {
    test('sets loaded status on empty results allowing UI to display empty state', () async {
      final fakeRepo = FakeSearchBookRepository();
      fakeRepo.searchResults = [];
      final provider = SearchProvider(searchBooksUseCase: SearchBooksUseCase(fakeRepo));

      expect(provider.status, SearchStatus.initial);
      provider.search('nonexistent_query');
      expect(provider.status, SearchStatus.loading);

      await Future.delayed(Duration.zero);

      expect(provider.status, SearchStatus.loaded);
      expect(provider.searchResults, isEmpty);
      provider.dispose();
    });

    test('stale query protection ignores out-of-order delayed responses', () async {
      final fakeRepo = FakeSearchBookRepository();
      final provider = SearchProvider(searchBooksUseCase: SearchBooksUseCase(fakeRepo));

      // Query 1 is slow
      fakeRepo.searchDelay = const Duration(milliseconds: 100);
      fakeRepo.searchResults = [
        const Book(isbn13: '1', title: 'Old Stale Book', authors: 'A', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0),
      ];
      provider.search('query1');

      // Query 2 is immediate
      fakeRepo.searchDelay = Duration.zero;
      fakeRepo.searchResults = [
        const Book(isbn13: '2', title: 'New Fresh Book', authors: 'B', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0),
      ];
      provider.search('query2');

      // Wait for slow query 1 to also complete
      await Future.delayed(const Duration(milliseconds: 150));

      expect(provider.status, SearchStatus.loaded);
      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.title, 'New Fresh Book');
      provider.dispose();
    });

    test('clearSearch resets status to initial and clears results', () async {
      final fakeRepo = FakeSearchBookRepository();
      fakeRepo.searchResults = [
        const Book(isbn13: '1', title: 'A', authors: 'B', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0),
      ];
      final provider = SearchProvider(searchBooksUseCase: SearchBooksUseCase(fakeRepo));
      provider.search('test');
      await Future.delayed(Duration.zero);
      expect(provider.searchResults.isNotEmpty, isTrue);

      provider.clearSearch();
      expect(provider.status, SearchStatus.initial);
      expect(provider.searchResults, isEmpty);
      expect(provider.lastQuery, isEmpty);
      provider.dispose();
    });
  });
}

class FakeSearchBookRepository extends FakeBookRepository {
  List<Book> searchResults = [];
  Duration? searchDelay;
  Exception? searchError;

  @override
  Future<List<Book>> searchBooks(String query) async {
    if (searchDelay != null) await Future.delayed(searchDelay!);
    if (searchError != null) throw searchError!;
    return searchResults;
  }
}
