import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book_model.dart';
import '../providers/auth_provider.dart';
import '../providers/book_provider.dart';
import '../providers/favorites_provider.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../widgets/book_card.dart';
import '../widgets/shimmer_loader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Book> _recommendations = [];
  bool _loadingRec = false;

  @override
  void initState() {
    super.initState();
    _loadPersonalisedRecs();
  }

  Future<void> _loadPersonalisedRecs() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;

    setState(() => _loadingRec = true);
    try {
      final recent = await SupabaseService.instance
          .getRecentlyViewed(auth.currentUser!.id, limit: 1);
      if (recent.isNotEmpty && mounted) {
        final recs = await ApiService.instance.getRecommendations(recent.first);
        if (mounted) setState(() => _recommendations = recs);
      }
    } catch (_) {
      // Graceful degradation
    } finally {
      if (mounted) setState(() => _loadingRec = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final books = context.watch<BookProvider>();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App bar ───────────────────────────────────────────────────────
            SliverAppBar(
              floating: true,
              snap: true,
              title: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.headlineMedium,
                  children: [
                    TextSpan(
                      text: 'Book',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800),
                    ),
                    const TextSpan(text: 'AI'),
                  ],
                ),
              ),
              actions: [
                if (auth.isLoggedIn)
                  IconButton(
                    icon: const Icon(Icons.person_outline),
                    onPressed: () => _showProfileSheet(context, auth),
                  )
                else
                  TextButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Sign In'),
                  ),
                const SizedBox(width: 8),
              ],
            ),

            SliverToBoxAdapter(
              child: RefreshIndicator(
                onRefresh: () => context.read<BookProvider>().fetchPopular(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // ── Search bar shortcut ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () => context.go('/search'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(children: [
                            Icon(Icons.search,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.7)),
                            const SizedBox(width: 10),
                            Text(
                              'Search books, authors…',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Featured book ────────────────────────────────────────
                    if (books.popularStatus == BookStatus.loaded &&
                        books.popularBooks.isNotEmpty) ...[
                      _SectionHeader(title: 'Featured'),
                      const SizedBox(height: 12),
                      FeaturedBookCard(book: books.popularBooks.first),
                      const SizedBox(height: 28),
                    ],

                    // ── Popular now ──────────────────────────────────────────
                    _SectionHeader(
                      title: 'Popular Now',
                      onSeeAll: () => context.go('/search'),
                    ),
                    const SizedBox(height: 12),
                    if (books.popularStatus == BookStatus.loading)
                      const ShimmerGrid()
                    else if (books.popularStatus == BookStatus.error)
                      _ErrorMessage(
                        message: books.popularError ?? 'Failed to load',
                        onRetry: () => books.fetchPopular(),
                      )
                    else
                      _HorizontalBookList(books: books.popularBooks),

                    const SizedBox(height: 28),

                    // ── Recommended for you ──────────────────────────────────
                    if (auth.isLoggedIn) ...[
                      _SectionHeader(title: 'Recommended For You'),
                      const SizedBox(height: 12),
                      if (_loadingRec)
                        const ShimmerGrid()
                      else if (_recommendations.isNotEmpty)
                        _HorizontalBookList(books: _recommendations)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'View a book to get personalised recommendations.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey),
                          ),
                        ),
                      const SizedBox(height: 28),
                    ],

                    // ── All books ────────────────────────────────────────────
                    _SectionHeader(title: 'All Books'),
                    const SizedBox(height: 12),
                    if (books.popularStatus == BookStatus.loading)
                      const ShimmerList()
                    else
                      ...books.popularBooks
                          .skip(1)
                          .take(15)
                          .map((b) => BookListTile(book: b)),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProfileSheet(BuildContext ctx, AuthProvider auth) {
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 48),
            const SizedBox(height: 8),
            Text(auth.currentUser?.email ?? '',
                style: Theme.of(sheetCtx).textTheme.titleMedium),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: const Text('My Favorites'),
              onTap: () {
                Navigator.pop(sheetCtx);
                ctx.go('/favorites');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () {
                ctx.read<AuthProvider>().logout();
                ctx.read<FavoritesProvider>().clearFavorites();
                Navigator.pop(sheetCtx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text('See All'),
            ),
        ],
      ),
    );
  }
}

class _HorizontalBookList extends StatelessWidget {
  const _HorizontalBookList({required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => BookCard(book: books[i]),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Icon(Icons.wifi_off_outlined,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
