import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/detail_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/recommendation_screen.dart';
import 'screens/register_screen.dart';
import 'screens/search_screen.dart';

class AppRouter {
  AppRouter._();

  static GoRouter createRouter(AuthProvider auth) {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: auth,
      redirect: (context, state) {
        final loggedIn = auth.isLoggedIn;
        final loggingIn = state.matchedLocation == '/login' ||
            state.matchedLocation == '/register';

        // Protect favorites
        if (state.matchedLocation == '/favorites' && !loggedIn) {
          return '/login';
        }
        // Don't send already-logged-in users to auth pages
        if (loggingIn && loggedIn) return '/';
        return null;
      },
      routes: [
        // ── Shell with bottom navigation ─────────────────────────────────────
        ShellRoute(
          builder: (context, state, child) => _ScaffoldWithNav(child: child),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: HomeScreen()),
            ),
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SearchScreen()),
            ),
            GoRoute(
              path: '/favorites',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: FavoritesScreen()),
            ),
          ],
        ),

        // ── Full-screen routes (no bottom nav) ───────────────────────────────
        GoRoute(
          path: '/book/:isbn',
          builder: (context, state) =>
              DetailScreen(isbn: state.pathParameters['isbn']!),
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

// ── Bottom navigation shell ──────────────────────────────────────────────────

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({required this.child});
  final Widget child;

  static const _tabs = [
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', path: '/'),
    _NavItem(icon: Icons.search_outlined, activeIcon: Icons.search, label: 'Search', path: '/search'),
    _NavItem(icon: Icons.bookmark_outline, activeIcon: Icons.bookmark, label: 'Saved', path: '/favorites'),
  ];

  int _indexFor(String location) {
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/favorites')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexFor(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_tabs[i].path),
        items: _tabs
            .map((t) => BottomNavigationBarItem(
                  icon: Icon(t.icon),
                  activeIcon: Icon(t.activeIcon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
}
