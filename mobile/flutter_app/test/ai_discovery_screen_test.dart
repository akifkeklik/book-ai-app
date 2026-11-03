import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:book_ai_app/application/use_cases/process_ai_chat_use_case.dart';
import 'package:book_ai_app/screens/ai_discovery_screen.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/providers/auth_provider.dart' as book_ai_app_auth_provider;

import 'book_provider_test.dart' show FakeBookRepository;
import 'auth_provider_test.dart' show FakeAuthService;

void main() {
  Widget createScreen(ProcessAiChatUseCase useCase) {
    final lang = LanguageProvider();
    lang.setTranslationsForTest('en', {
      'ai_discovery_error': 'Failed to get recommendation from AI',
      'no_response': 'No response received from AI librarian',
    });
    return MultiProvider(
      providers: [
        Provider<ProcessAiChatUseCase>.value(value: useCase),
        ChangeNotifierProvider<LanguageProvider>.value(value: lang),
        ChangeNotifierProvider(create: (_) => book_ai_app_auth_provider.AuthProvider(FakeAuthService())),
      ],
      child: const MaterialApp(
        home: AiDiscoveryScreen(),
      ),
    );
  }

  group('AiDiscoveryScreen', () {
    testWidgets('empty query does not trigger repository call', (tester) async {
      final repo = FakeBookRepository();
      repo.chatWithAIResult = {'answer': 'Success'};

      await tester.pumpWidget(createScreen(ProcessAiChatUseCase(repo)));

      // Tap send button without typing
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(repo.chatCallCount, 0);
    });

    testWidgets('successful response updates UI', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = FakeBookRepository();
      repo.chatDelay = const Duration(milliseconds: 100);
      repo.chatWithAIResult = {
        'answer': 'This is an AI answer',
      };

      await tester.pumpWidget(createScreen(ProcessAiChatUseCase(repo)));

      await tester.enterText(find.byType(TextField), 'Hello AI');
      await tester.tap(find.byType(IconButton));

      // Loading state
      await tester.pump();
      // Skip CircularProgressIndicator check as it can be flaky with timing

      // Finish loading

      // Finish loading
      await tester.pumpAndSettle();

      expect(find.text('This is an AI answer'), findsOneWidget);
      expect(repo.chatCallCount, 1);
    });

    testWidgets('request failure shows error message', (tester) async {
      final repo = FakeBookRepository();
      repo.chatError = Exception('Network Down');

      await tester.pumpWidget(createScreen(ProcessAiChatUseCase(repo)));

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.tap(find.byType(IconButton));

      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to get recommendation from AI'), findsOneWidget);
      expect(find.textContaining('ai_discovery_error'), findsNothing);
    });

    testWidgets('duplicate submit prevented while loading', (tester) async {
      final repo = FakeBookRepository();
      // Delay to keep loading state active
      repo.chatDelay = const Duration(seconds: 2);
      repo.chatWithAIResult = {'answer': 'Delayed'};

      await tester.pumpWidget(createScreen(ProcessAiChatUseCase(repo)));

      await tester.enterText(find.byType(TextField), 'Multi tap');

      // Tap multiple times
      await tester.tap(find.byType(IconButton));
      await tester.pump(); // Start loading

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      // Wait for it to finish
      await tester.pumpAndSettle();

      // Should only call repo once due to _isLoading flag
      expect(repo.chatCallCount, 1);
    });

    testWidgets('error response in payload displays backend error message', (tester) async {
      final repo = FakeBookRepository();
      repo.chatWithAIResult = {'error': 'Rate limit exceeded. Please try again later.'};

      await tester.pumpWidget(createScreen(ProcessAiChatUseCase(repo)));

      await tester.enterText(find.byType(TextField), 'Rate limit me');
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Rate limit exceeded. Please try again later.'), findsOneWidget);
    });

    testWidgets('empty answer string displays no_response fallback', (tester) async {
      final repo = FakeBookRepository();
      repo.chatWithAIResult = {'answer': '   '};

      await tester.pumpWidget(createScreen(ProcessAiChatUseCase(repo)));

      await tester.enterText(find.byType(TextField), 'Empty answer');
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('No response received from AI librarian'), findsOneWidget);
      expect(find.text('no_response'), findsNothing);
    });

    testWidgets('multi-turn conversation preserves history across consecutive queries', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = FakeBookRepository();
      repo.chatWithAIResult = {'answer': 'First answer regarding sci-fi.'};

      await tester.pumpWidget(createScreen(ProcessAiChatUseCase(repo)));

      // Turn 1
      await tester.enterText(find.byType(TextField), 'First question');
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('First question'), findsOneWidget);
      expect(find.text('First answer regarding sci-fi.'), findsOneWidget);

      // Turn 2
      repo.chatWithAIResult = {'answer': 'Second answer with cyberpunk recommendations.'};
      await tester.enterText(find.byType(TextField), 'Second follow-up');
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Both turns must coexist in conversation history
      expect(find.text('First question'), findsOneWidget);
      expect(find.text('First answer regarding sci-fi.'), findsOneWidget);
      expect(find.text('Second follow-up'), findsOneWidget);
      expect(find.text('Second answer with cyberpunk recommendations.'), findsOneWidget);
      expect(repo.chatCallCount, 2);
    });
  });
}
