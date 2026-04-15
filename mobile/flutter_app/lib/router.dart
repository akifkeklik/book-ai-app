import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'models/book_model.dart';
import 'providers/auth_provider.dart';
import 'providers/language_provider.dart';
import 'screens/categories_screen.dart';
import 'screens/category_timeline_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/recommendation_screen.dart';
import 'screens/register_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';

class AppRouter {
  AppRouter._();

  static GoRouter createRouter(AuthProvider auth) {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: auth,
      redirect: (context, state) {
        // Senior Logic: Wait for auth to settle!
        if (auth.isLoading) {
          return null; // Don't move while loading
        }

        final loggedIn = auth.isLoggedIn;
        final isAuthRoute = state.matchedLocation == '/login' ||
            state.matchedLocation == '/register';

        // 1. If NOT logged in and NOT on an auth page, redirect to LOGIN (not register!)
        if (!loggedIn && !isAuthRoute) {
          return '/login';
        }

        // 2. If logged in and trying to go to LOGIN/REGISTER, redirect to HOME
        if (loggedIn && isAuthRoute) {
          return '/';
        }

        return null;
      },
      routes: [
        ShellRoute(
          builder: (context, state, child) => _ScaffoldWithNav(child: child),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => CustomTransitionPage(
                child: const HomeScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(opacity: animation, child: child),
              ),
            ),
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) => CustomTransitionPage(
                child: const SearchScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(opacity: animation, child: child),
              ),
            ),
            GoRoute(
              path: '/categories',
              pageBuilder: (context, state) => CustomTransitionPage(
                child: const CategoriesScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(opacity: animation, child: child),
              ),
            ),
            GoRoute(
              path: '/favorites',
              pageBuilder: (context, state) => CustomTransitionPage(
                child: const FavoritesScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(opacity: animation, child: child),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/category/:genre',
          builder: (context, state) => CategoryTimelineScreen(
            genre: Uri.decodeComponent(state.pathParameters['genre']!),
          ),
        ),
        GoRoute(
          path: '/book/:isbn',
          builder: (context, state) => DetailScreen(
            isbn: state.pathParameters['isbn']!,
            initialBook: state.extra is Book ? state.extra as Book : null,
          ),
        ),
        GoRoute(
          path: '/recommend/:title',
          builder: (context, state) => RecommendationScreen(
            bookTitle: Uri.decodeComponent(state.pathParameters['title']!),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({required this.child});
  final Widget child;

  int _indexFor(String location) {
    if (location.startsWith('/categories')) return 1;
    if (location.startsWith('/search')) return 2;
    if (location.startsWith('/favorites')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexFor(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.go('/categories');
              break;
            case 2:
              context.go('/search');
              break;
            case 3:
              context.go('/favorites');
              break;
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: context.tr('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: context.tr('categories'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.search_outlined),
            selectedIcon: const Icon(Icons.search),
            label: context.tr('search'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmark_outline),
            selectedIcon: const Icon(Icons.bookmark),
            label: context.tr('saved'),
          ),
        ],
      ),
    );
  }
}
