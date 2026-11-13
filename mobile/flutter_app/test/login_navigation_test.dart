import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:book_ai_app/providers/auth_provider.dart';
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/screens/login_screen.dart';

import 'auth_provider_test.dart' show FakeAuthService;
import 'book_detail_bottom_sheet_test.dart' show DetailTestSupabaseService;

/// Regression: a successful login used to navigate twice (router redirect and
/// LoginScreen.context.go), reading GoRouterState from the login page while it
/// was being removed. That tripped Flutter's `_dependents.isEmpty` assertion.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget buildApp(AuthProvider auth, {String initialLocation = '/login'}) {
    final router = GoRouter(
      initialLocation: initialLocation,
      refreshListenable: auth,
      // Same auth-route rule as AppRouter.redirect.
      redirect: (context, state) {
        if (auth.isLoading) return null;
        final isAuthRoute = state.matchedLocation == '/login';
        if (auth.isLoggedIn && isAuthRoute) {
          final redirect = state.uri.queryParameters['redirect'];
          return (redirect != null && redirect.isNotEmpty) ? redirect : '/';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
        GoRoute(path: '/notes', builder: (_, __) => const Text('NOTES')),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => FavoritesProvider(DetailTestSupabaseService())),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'ok@test.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  testWidgets('successful login lands on home without framework assertions', (tester) async {
    final auth = AuthProvider(FakeAuthService());
    await tester.pumpWidget(buildApp(auth));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await login(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('successful login honours the redirect target', (tester) async {
    final auth = AuthProvider(FakeAuthService());
    await tester.pumpWidget(buildApp(auth, initialLocation: '/login?redirect=%2Fnotes'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await login(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('NOTES'), findsOneWidget);
  });

  testWidgets('remember-me email is saved even though the router leaves the page', (tester) async {
    final auth = AuthProvider(FakeAuthService());
    await tester.pumpWidget(buildApp(auth));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await login(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_email'), 'ok@test.com');
  });
}
