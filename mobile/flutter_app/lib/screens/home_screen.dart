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
import '../application/use_cases/manage_user_profile_use_case.dart';
import '../widgets/book_card.dart';

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
    // Disabled infinite scroll for Dashboard structure
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
        final profile = await context.read<ManageUserProfileUseCase>().getUserProfile(auth.currentUser!.id);
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
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Consumer<AuthProvider>(
                          builder: (context, auth, _) {
                            final email = auth.currentUser?.email;
                            final name = email != null ? email.split('@').first : '';
                            final displayName = name.isNotEmpty ? '${name[0].toUpperCase()}${name.substring(1)}' : '';
                            return Text(
                              displayName.isNotEmpty ? 'Hello, $displayName' : context.tr('app_name'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white70 : DesignSystem.textLightSecondary,
                                letterSpacing: -0.5,
                              ),
                            );
                          },
                        ),
                        Text(
                          context.tr('explore'),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                            color: isDark ? Colors.white : DesignSystem.textLightPrimary,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      _GlassIconButton(
                        icon: Icons.search,
                        tooltip: context.tr('search'),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.go('/search');
                        },
                      ),
                      const SizedBox(width: DesignSystem.spacing8),
                      _GlassIconButton(
                        icon: Icons.settings_outlined,
                        tooltip: context.tr('settings'),
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
                                      child: Text(
                                        context.tr('ai_discovery_badge'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: DesignSystem.spacing12),
                                    Text(
                                      context.tr('ai_discovery_title'),
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: DesignSystem.spacing8),
                                    Text(
                                      context.tr('ai_discovery_desc'),
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
                          return const SizedBox.shrink(); // Don't show empty state here, just hide personalized section
                        }

                        if (recommendations.status == RecommendationStatus.loading) {
                           return Padding(
                             padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing16, vertical: DesignSystem.spacing8),
                             child: _Section(
                               title: context.tr('recommended_for_you'),
                               child: const SkeletonList(height: 280),
                             ),
                           );
                        }

                        if (recommendations.personalizedRecs.isEmpty) {
                           return const SizedBox.shrink(); // Hidden if no real personalized data
                        }

                        return Padding(
                          padding: const EdgeInsets.only(left: DesignSystem.spacing16, right: DesignSystem.spacing16, top: DesignSystem.spacing8),
                          child: _Section(
                            title: context.tr('recommended_for_you'),
                            child: _HorizontalRecs(books: recommendations.personalizedRecs),
                          ),
                        );
                      },
                    ),
                  ),



                  // ── Trending / Popular (Horizontal) ─────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: DesignSystem.spacing16, right: DesignSystem.spacing16, top: DesignSystem.spacing8),
                      child: _Section(
                        title: context.tr('popular_books'),
                        child: catalog.status == CatalogStatus.loading
                            ? const SkeletonList(height: 280)
                            : (catalog.status == CatalogStatus.error && catalog.popularBooks.isEmpty)
                                ? Center(
                                    child: TextButton(
                                      onPressed: () => catalog.fetchPopular(force: true),
                                      child: Text(context.tr('retry')),
                                    ),
                                  )
                                : _HorizontalRecs(books: catalog.popularBooks.take(15).toList()),
                      ),
                    ),
                  ),

                  // ── Categories Discovery ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: DesignSystem.spacing16, right: DesignSystem.spacing16, top: DesignSystem.spacing8),
                      child: _Section(
                        title: context.tr('categories'),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            children: [
                              for (var i = 0; i < (catalog.defaultGenres.length < 8 ? catalog.defaultGenres.length : 8); i++) ...[
                                _CategoryChip(
                                  category: catalog.defaultGenres[i],
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    context.push('/category/${Uri.encodeComponent(catalog.defaultGenres[i])}');
                                  },
                                ),
                                if (i < 7) const SizedBox(width: DesignSystem.spacing8),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
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
  final String? tooltip;

  const _GlassIconButton({required this.icon, required this.onPressed, this.tooltip});

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
              tooltip: tooltip,
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

class _CategoryChip extends StatelessWidget {
  final String category;
  final VoidCallback onTap;

  const _CategoryChip({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      label: Text(
        context.trGenre(category),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: onTap,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing12, vertical: DesignSystem.spacing8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
    );
  }
}

class _HorizontalRecs extends StatelessWidget {
  const _HorizontalRecs({required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < books.length; i++) ...[
              BookCard(book: books[i]),
              if (i < books.length - 1)
                const SizedBox(width: DesignSystem.spacing16),
            ]
          ],
        ),
      ),
    );
  }
}
