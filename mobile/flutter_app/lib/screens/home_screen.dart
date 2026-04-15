import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book_model.dart';
import '../providers/auth_provider.dart';
import '../providers/book_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/language_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_loader.dart';

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
      context.read<BookProvider>().fetchMorePopular();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final books = context.read<BookProvider>();
    final auth = context.read<AuthProvider>();
    final favs = context.read<FavoritesProvider>();

    books.fetchPopular();
    if (auth.isLoggedIn) {
      // Senior Solution: Load favorites first, then trigger recommendations
      // to ensure state is synced across the app layers.
      await favs.loadFavorites(auth.currentUser!.id);
      
      // Senior Solution: Auto-onboarding for users with zero favorites
      // We check if the list is still empty after loading.
      if (favs.favorites.isEmpty && mounted) {
        // Double check profile to avoid loop if they already onboarded but didn't favorite
        final profile = await _supabase.getUserProfile(auth.currentUser!.id);
        if (profile == null && mounted) {
          context.go('/onboarding');
          return;
        }
      }
      
      books.fetchPersonalizedRecs(auth.currentUser!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            await context.read<BookProvider>().fetchPopular(force: true);
          },
          child: Consumer<BookProvider>(
            builder: (context, books, _) {
              return CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── App Bar ────────────────────────────────────────────────────
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Libris',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (books.totalBooksCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${books.totalBooksCount}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push('/settings');
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),

                  // ── Search & Recommendations ───────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search shortcut
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              context.go('/search');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              decoration: BoxDecoration(
                                color: theme.cardColor.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                    color:
                                        colorScheme.primary.withOpacity(0.1)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.search,
                                      color:
                                          colorScheme.primary.withOpacity(0.7)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      context.tr('search_placeholder'),
                                      style: TextStyle(
                                          color: colorScheme.onSurface
                                              .withOpacity(0.5)),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Personalized Recs
                          Consumer2<AuthProvider, FavoritesProvider>(
                            builder: (context, auth, favProv, _) {
                              if (!auth.isLoggedIn)
                                return const SizedBox.shrink();

                              if (favProv.favorites.isEmpty &&
                                  !favProv.isLoading) {
                                return _Section(
                                  title: context.tr('recommended_for_you'),
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color:
                                          colorScheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: colorScheme.primary
                                              .withOpacity(0.2)),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.favorite_rounded,
                                            color: colorScheme.primary
                                                .withOpacity(0.7),
                                            size: 48),
                                        const SizedBox(height: 16),
                                        Text(
                                          context.tr('recommended_empty_title'),
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          context
                                              .tr('recommended_empty_subtitle'),
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              return _Section(
                                title: context.tr('recommended_for_you'),
                                child: books.personalizedStatus ==
                                        BookStatus.loading
                                    ? const SkeletonList(height: 330)
                                    : _HorizontalRecs(
                                        books: books.personalizedRecs),
                              );
                            },
                          ),

                          const SizedBox(height: 12),
                          _Section(
                            title: context.tr('popular_books'),
                            child: books.popularStatus == BookStatus.loading &&
                                    books.popularBooks.isEmpty
                                ? const SkeletonList(height: 330)
                                : _HorizontalRecs(books: books.popularBooks),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── All Books Grid (Infinite Scroll) ──────────────────────────
                  if (books.popularStatus == BookStatus.loading &&
                      books.popularBooks.isEmpty)
                    const SliverToBoxAdapter(child: SkeletonList(height: 330))
                  else if (books.popularStatus == BookStatus.error &&
                      books.popularBooks.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(Icons.cloud_off,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(context.tr('error_loading_books')),
                            TextButton(
                              onPressed: () => books.fetchPopular(force: true),
                              child: Text(context.tr('retry')),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (books.popularBooks.isEmpty)
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
                            return BookListTile(
                                book: books.popularBooks[index]);
                          },
                          childCount: books.popularBooks.length,
                        ),
                      ),
                    ),

                  // ── Loading More Indicator ────────────────────────────────────
                  SliverToBoxAdapter(
                    child: books.isLoadingMore
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        child,
        const SizedBox(height: 24),
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
      height: 358,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) => BookCard(book: books[index]),
      ),
    );
  }
}
