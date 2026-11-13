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
import '../widgets/saas_widgets.dart';
import '../providers/language_provider.dart';
import '../theme/design_system.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ScrollController _scrollController;
  String? _preferredGenre;
  String? _loadedUserId;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initData();
    });
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
    final profileUseCase = context.read<ManageUserProfileUseCase>();

    catalog.fetchPopular();
    if (auth.isLoggedIn && auth.currentUser != null) {
      final uid = auth.currentUser!.id;
      await favs.loadFavorites(uid);
      if (!mounted || auth.currentUser?.id != uid) return;

      try {
        final profile = await profileUseCase.getUserProfile(uid);
        if (!mounted || auth.currentUser?.id != uid) return;
        if (profile != null) {
          final genres = profile['preferred_genres'] as List<dynamic>?;
          if (genres != null && genres.isNotEmpty) {
            setState(() {
              _preferredGenre = genres.first.toString();
            });
          }
        } else if (favs.favorites.isEmpty) {
          context.go('/onboarding');
          return;
        }
      } catch (_) {
        // Safe offline/fallback: do not trap user in redirect
      }

      if (!mounted || auth.currentUser?.id != uid) return;
      recommendations.fetchPersonalizedRecs(uid, catalog.popularBooks);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUid = auth.currentUser?.id;
    if (_loadedUserId != currentUid) {
      _loadedUserId = currentUid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _preferredGenre = null);
        context.read<RecommendationProvider>().clearUserData();
        context.read<FavoritesProvider>().clearFavorites();
        if (currentUid != null) {
          _initData();
        }
      });
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            final catalog = context.read<CatalogProvider>();
            final auth = context.read<AuthProvider>();
            final favs = context.read<FavoritesProvider>();
            final recs = context.read<RecommendationProvider>();
            final profileUseCase = context.read<ManageUserProfileUseCase>();
            await catalog.fetchPopular(force: true);
            if (auth.isLoggedIn && auth.currentUser != null) {
              final uid = auth.currentUser!.id;
              await favs.loadFavorites(uid);
              if (!mounted || auth.currentUser?.id != uid) return;
              try {
                final profile = await profileUseCase.getUserProfile(uid);
                if (!mounted || auth.currentUser?.id != uid) return;
                if (profile != null) {
                  final genres = profile['preferred_genres'] as List<dynamic>?;
                  if (genres != null && genres.isNotEmpty) {
                    setState(() {
                      _preferredGenre = genres.first.toString();
                    });
                  }
                }
              } catch (_) {}
              if (!mounted || auth.currentUser?.id != uid) return;
              await recs.fetchPersonalizedRecs(uid, catalog.popularBooks, force: true);
            }
          },
          child: Consumer2<CatalogProvider, RecommendationProvider>(
            builder: (context, catalog, recommendations, _) {
              return CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Premium App Bar ───────────────────────────────────────────
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    elevation: 0,
                    scrolledUnderElevation: 2,
                    backgroundColor: theme.scaffoldBackgroundColor,
                    surfaceTintColor: Colors.transparent,
                    toolbarHeight: 74,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Consumer<AuthProvider>(
                          builder: (context, auth, _) {
                            final email = auth.currentUser?.email;
                            final name = email != null ? email.split('@').first : '';
                            final displayName = name.isNotEmpty ? '${name[0].toUpperCase()}${name.substring(1)}' : '';
                            return Text(
                              displayName.isNotEmpty
                                  ? context.tr('hello_user', args: {'name': displayName})
                                  : context.tr('app_name'),
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
                        icon: Icons.psychology_outlined,
                        tooltip: context.tr('nav_learning'),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push('/learning');
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
                              colors: isDark
                                  ? [
                                      DesignSystem.saasNavy800,
                                      DesignSystem.saasNavy900,
                                    ]
                                  : [
                                      theme.colorScheme.primary.withOpacity(0.9),
                                      DesignSystem.primaryDark,
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: DesignSystem.borderRadiusLarge,
                            border: Border.all(
                              color: isDark ? DesignSystem.electricBlueBorder : Colors.transparent,
                              width: 1.2,
                            ),
                            boxShadow: isDark ? DesignSystem.saasCardHoverShadow(true) : DesignSystem.shadowLg(false),
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
                                        color: isDark ? DesignSystem.electricBlueMuted : Colors.white.withOpacity(0.2),
                                        borderRadius: DesignSystem.borderRadiusPill,
                                        border: Border.all(color: isDark ? DesignSystem.electricBlueBorder : Colors.transparent),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SaasPulseDot(color: DesignSystem.electricBlue, size: 6),
                                          const SizedBox(width: 5),
                                          Text(
                                            context.tr('ai_discovery_badge'),
                                            style: TextStyle(
                                              color: isDark ? DesignSystem.electricBlue : Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ],
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

                  // ── Dashboard SaaS Metrics Strip ──────────────────────────────
                  Consumer<FavoritesProvider>(
                    builder: (context, favProv, _) {
                      final finishedCount = favProv.favorites.where((f) => f.status == 'finished').length;
                      final readingCount = favProv.favorites.where((f) => f.status == 'reading').length;
                      final queueCount = favProv.favorites.where((f) => f.status == 'want_to_read').length;

                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing16, vertical: DesignSystem.spacing4),
                          child: Row(
                            children: [
                              Expanded(
                                child: SaasMetricCard(
                                  label: context.tr('status_reading'),
                                  value: '$readingCount',
                                  icon: Icons.auto_stories_rounded,
                                  accentColor: const Color(0xFFF59E0B),
                                  pulseDotColor: const Color(0xFFF59E0B),
                                  footerText: context.tr('ui_active'),
                                ),
                              ),
                              const SizedBox(width: DesignSystem.spacing8),
                              Expanded(
                                child: SaasMetricCard(
                                  label: context.tr('status_want_to_read'),
                                  value: '$queueCount',
                                  icon: Icons.bookmark_added_rounded,
                                  accentColor: DesignSystem.electricBlue,
                                  pulseDotColor: DesignSystem.electricBlue,
                                  footerText: context.tr('ui_in_queue'),
                                ),
                              ),
                              const SizedBox(width: DesignSystem.spacing8),
                              Expanded(
                                child: SaasMetricCard(
                                  label: context.tr('status_finished'),
                                  value: '$finishedCount',
                                  icon: Icons.check_circle_rounded,
                                  accentColor: const Color(0xFF10B981),
                                  pulseDotColor: const Color(0xFF10B981),
                                  footerText: context.tr('tab_finished'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // ── Taste Profile Calibration Prompt ───────────────────────────
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (!auth.isLoggedIn || _preferredGenre != null) return const SliverToBoxAdapter(child: SizedBox.shrink());
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing16, vertical: DesignSystem.spacing4),
                          child: Container(
                            padding: const EdgeInsets.all(DesignSystem.spacing16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.08),
                              borderRadius: DesignSystem.borderRadiusLarge,
                              border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
                                const SizedBox(width: DesignSystem.spacing12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.tr('taste_profile'),
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        context.tr('select_genres_hint'),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context.push('/onboarding'),
                                  child: Text(context.tr('next')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // ── Recommendations (Picked for you) ───────────────────────────
                  SliverToBoxAdapter(
                    child: Consumer2<AuthProvider, FavoritesProvider>(
                      builder: (context, auth, favProv, _) {
                        if (!auth.isLoggedIn) return const SizedBox.shrink();

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
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing16, vertical: DesignSystem.spacing8),
                            child: _Section(
                              title: context.tr('recommended_for_you'),
                              child: Container(
                                padding: const EdgeInsets.all(DesignSystem.spacing20),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                                  borderRadius: DesignSystem.borderRadiusLarge,
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withOpacity(0.15),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.auto_awesome,
                                        color: theme.colorScheme.primary,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: DesignSystem.spacing16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            context.tr('recommended_empty_title'),
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            context.tr('recommended_empty_subtitle'),
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                                            ),
                                          ),
                                        ],
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
                            trailing: TextButton(
                              onPressed: () => context.push('/recommendations/personalized'),
                              child: Text(
                                context.tr('see_all'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            child: _HorizontalRecs(books: recommendations.personalizedRecs),
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Your Reading List ──────────────────────────────────────────
                  Consumer2<AuthProvider, FavoritesProvider>(
                    builder: (context, auth, favProv, _) {
                      if (!auth.isLoggedIn || favProv.favorites.isEmpty) {
                        return const SliverToBoxAdapter(child: SizedBox.shrink());
                      }
                      final readingListBooks = favProv.favorites.map((f) => Book(
                        isbn13: f.isbn13,
                        title: f.bookTitle,
                        authors: '',
                        categories: '',
                        description: '',
                        thumbnail: f.thumbnail,
                        averageRating: 0.0,
                        ratingsCount: 0,
                        publishedDate: '',
                        pageCount: 0,
                      )).toList();

                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(left: DesignSystem.spacing16, right: DesignSystem.spacing16, top: DesignSystem.spacing8),
                          child: _Section(
                            title: context.tr('your_reading_list'),
                            child: _HorizontalRecs(books: readingListBooks),
                          ),
                        ),
                      );
                    },
                  ),

                  // ── Because You Enjoy {primaryGenre} ───────────────────────────
                  if (_preferredGenre != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(left: DesignSystem.spacing16, right: DesignSystem.spacing16, top: DesignSystem.spacing8),
                        child: Builder(
                          builder: (context) {
                            final genreBooks = catalog.popularBooks
                                .where((b) => b.categories.toLowerCase().contains(_preferredGenre!.toLowerCase()))
                                .take(10)
                                .toList();
                            if (genreBooks.isEmpty) return const SizedBox.shrink();
                            return _Section(
                              title: context.tr('because_you_enjoy', args: {'genre': context.trGenre(_preferredGenre!)}),
                              child: _HorizontalRecs(books: genreBooks),
                            );
                          },
                        ),
                      ),
                    ),

                  // ── Trending / Popular (Horizontal) ─────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: DesignSystem.spacing16, right: DesignSystem.spacing16, top: DesignSystem.spacing8),
                      child: _Section(
                        title: context.tr('popular_books'),
                        trailing: catalog.isFromCache
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.cloud_off_rounded, size: 12, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                                    const SizedBox(width: 4),
                                    Text(
                                      context.tr('offline_catalog_cached'),
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontSize: 10,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : null,
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
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

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
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            if (trailing != null) trailing!,
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
