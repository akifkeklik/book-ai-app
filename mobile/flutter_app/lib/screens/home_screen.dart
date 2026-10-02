import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/entities/book.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/recommendation_provider.dart';
import '../providers/favorites_provider.dart';
import '../domain/repositories/book_repository.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_loader.dart';
import '../providers/language_provider.dart';
import '../theme/design_system.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _initData();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      context.read<CatalogProvider>().fetchMorePopular();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final catalog = context.read<CatalogProvider>();
    final recommendations = context.read<RecommendationProvider>();
    final auth = context.read<AuthProvider>();
    final favs = context.read<FavoritesProvider>();

    catalog.fetchPopular();
    if (auth.isLoggedIn) {
      await favs.loadFavorites(auth.currentUser!.id);

      if (favs.favorites.isEmpty && mounted) {
        final profile = await context.read<BookRepository>().getUserProfile(auth.currentUser!.id);
        if (profile == null && mounted) {
          context.go('/onboarding');
          return;
        }
      }

      recommendations.fetchPersonalizedRecs(auth.currentUser!.id, catalog.popularBooks);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            await context.read<CatalogProvider>().fetchPopular(force: true);
          },
          child: Consumer2<CatalogProvider, RecommendationProvider>(
            builder: (context, catalog, recommendations, _) {
              return CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Premium App Bar ───────────────────────────────────────────
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    toolbarHeight: 70,
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [theme.colorScheme.primary, DesignSystem.primaryDark],
                            ),
                            borderRadius: DesignSystem.borderRadiusSmall,
                          ),
                          child: const Icon(Icons.auto_stories, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: DesignSystem.spacing12),
                        Text(
                          'Libris',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.5,
                            color: isDark ? Colors.white : DesignSystem.textLightPrimary,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      _GlassIconButton(
                        icon: Icons.search,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.go('/search');
                        },
                      ),
                      const SizedBox(width: DesignSystem.spacing8),
                      _GlassIconButton(
                        icon: Icons.settings_outlined,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push('/settings');
                        },
                      ),
                      const SizedBox(width: DesignSystem.spacing16),
                    ],
                  ),

                  // ── AI Discovery Banner ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(DesignSystem.spacing16),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          context.push('/ai');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(DesignSystem.spacing24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary.withOpacity(0.9),
                                DesignSystem.primaryDark,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: DesignSystem.borderRadiusLarge,
                            boxShadow: DesignSystem.shadowLg(isDark),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: DesignSystem.borderRadiusPill,
                                      ),
                                      child: const Text(
                                        'AI DISCOVERY',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: DesignSystem.spacing12),
                                    Text(
                                      'Find your next favorite book using AI',
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: DesignSystem.spacing8),
                                    Text(
                                      'Describe what you want to read, and we\'ll find it.',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: DesignSystem.spacing16),
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Recommendations ───────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Consumer2<AuthProvider, FavoritesProvider>(
                      builder: (context, auth, favProv, _) {
                        if (!auth.isLoggedIn) return const SizedBox.shrink();

                        if (favProv.favorites.isEmpty && !favProv.isLoading) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing16),
                            child: _Section(
                              title: context.tr('recommended_for_you'),
                              child: Container(
                                padding: const EdgeInsets.all(DesignSystem.spacing24),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.05),
                                  borderRadius: DesignSystem.borderRadiusLarge,
                                  border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.favorite_rounded,
                                        color: theme.colorScheme.primary.withOpacity(0.5), size: 48),
                                    const SizedBox(height: DesignSystem.spacing16),
                                    Text(
                                      context.tr('recommended_empty_title'),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: DesignSystem.spacing8),
                                    Text(
                                      context.tr('recommended_empty_subtitle'),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: isDark ? Colors.white70 : DesignSystem.textLightSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.only(left: DesignSystem.spacing16, right: DesignSystem.spacing16, top: DesignSystem.spacing8),
                          child: _Section(
                            title: context.tr('recommended_for_you'),
                            child: recommendations.status == RecommendationStatus.loading
                                ? const SkeletonList(height: 280)
                                : _HorizontalRecs(books: recommendations.personalizedRecs),
                          ),
                        );
                      },
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing16),
                      child: _Section(
                        title: context.tr('popular_books'),
                        child: catalog.status == CatalogStatus.loading && catalog.popularBooks.isEmpty
                            ? const SkeletonList(height: 280)
                            : _HorizontalRecs(books: catalog.popularBooks),
                      ),
                    ),
                  ),

                  // ── All Books Grid (Infinite Scroll) ──────────────────────────
                  if (catalog.status == CatalogStatus.error && catalog.popularBooks.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(context.tr('error_loading_books')),
                            TextButton(
                              onPressed: () => catalog.fetchPopular(force: true),
                              child: Text(context.tr('retry')),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (catalog.popularBooks.isEmpty && catalog.status != CatalogStatus.loading)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: LibrisEmptyState(
                          icon: Icons.auto_stories_outlined,
                          title: context.tr('no_books_found'),
                          message: context.tr('no_books_message'),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return BookListTile(book: catalog.popularBooks[index]);
                          },
                          childCount: catalog.popularBooks.length,
                        ),
                      ),
                    ),

                  // ── Loading More Indicator ────────────────────────────────────
                  SliverToBoxAdapter(
                    child: catalog.isLoadingMore
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : const SizedBox(height: 80),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _GlassIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: ClipRRect(
        borderRadius: DesignSystem.borderRadiusPill,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
            shape: const CircleBorder(),
            child: IconButton(
              icon: Icon(icon, color: isDark ? Colors.white : DesignSystem.textLightPrimary),
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: DesignSystem.spacing8),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignSystem.spacing16),
        child,
        const SizedBox(height: DesignSystem.spacing32),
      ],
    );
  }
}

class _HorizontalRecs extends StatelessWidget {
  const _HorizontalRecs({required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 310, // Adjusted for new design system book card
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        clipBehavior: Clip.none,
        separatorBuilder: (_, __) => const SizedBox(width: DesignSystem.spacing16),
        itemBuilder: (_, index) => BookCard(book: books[index]),
      ),
    );
  }
}
