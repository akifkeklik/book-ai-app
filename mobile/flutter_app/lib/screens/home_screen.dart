import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book_model.dart';
import '../providers/auth_provider.dart';
import '../providers/book_provider.dart';
import '../providers/language_provider.dart';
import '../providers/favorites_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/shimmer_loader.dart';

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
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
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
    
    books.fetchPopular();
    if (auth.isLoggedIn) {
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
          child: CustomScrollView(
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
                    Selector<BookProvider, int>(
                      selector: (_, p) => p.totalBooksCount,
                      builder: (context, count, _) => count > 0 ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ) : const SizedBox.shrink(),
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
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: theme.cardColor.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: colorScheme.primary.withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search, color: colorScheme.primary.withOpacity(0.7)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.tr('search_placeholder'),
                                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
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
                          if (!auth.isLoggedIn) return const SizedBox.shrink();

                          if (favProv.favorites.isEmpty && !favProv.isLoading) {
                            return _Section(
                              title: context.tr('recommended_for_you'),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.favorite_border, color: colorScheme.primary, size: 40),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Kalbini bıraktığın kitaplar arttıkça sana özel öneriler belirecek.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return _Section(
                            title: context.tr('recommended_for_you'),
                            child: Consumer<BookProvider>(
                              builder: (context, books, _) {
                                if (books.personalizedStatus == BookStatus.loading) {
                                  return const ShimmerGrid();
                                }
                                return _HorizontalRecs(books: books.personalizedRecs);
                              },
                            ),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 12),
                      _Section(
                        title: context.tr('popular_books'),
                        child: Consumer<BookProvider>(
                          builder: (context, books, _) {
                            if (books.popularStatus == BookStatus.loading && books.popularBooks.isEmpty) {
                              return const ShimmerGrid();
                            }
                            return _HorizontalRecs(books: books.popularBooks);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── All Books Grid (Infinite Scroll) ──────────────────────────
              Consumer<BookProvider>(
                builder: (context, books, _) {
                  if (books.popularStatus == BookStatus.loading && books.popularBooks.isEmpty) {
                    return const SliverToBoxAdapter(child: ShimmerList());
                  }

                  if (books.popularStatus == BookStatus.error && books.popularBooks.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(context.tr('error_loading_books')),
                            TextButton(
                              onPressed: () => books.fetchPopular(force: true),
                              child: Text(context.tr('retry')),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (books.popularBooks.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: LibrisEmptyState(
                          icon: Icons.auto_stories_outlined,
                          title: context.tr('no_books_found'),
                          message: context.tr('no_books_message'),
                        ),
                      ),
                    );
                  }
                  
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return BookListTile(book: books.popularBooks[index]);
                        },
                        childCount: books.popularBooks.length,
                      ),
                    ),
                  );
                },
              ),

              // ── Loading More Indicator ────────────────────────────────────
              Selector<BookProvider, bool>(
                selector: (_, p) => p.isLoadingMore,
                builder: (context, loading, _) => SliverToBoxAdapter(
                  child: loading 
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : const SizedBox(height: 80),
                ),
              ),
            ],
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
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
      height: 330,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) => BookCard(book: books[index]),
      ),
    );
  }
}
