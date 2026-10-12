import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:book_ai_app/application/use_cases/search_books_use_case.dart';
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
}
