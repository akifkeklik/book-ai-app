import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
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

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.isbn});
  final String isbn;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Book? _book;
  List<Book> _similar = [];
  bool _loadingBook = true;
  bool _loadingSimilar = false;
  String? _bookError;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _fetchBook();
  }

  Future<void> _fetchBook() async {
    setState(() => _loadingBook = true);
    try {
      final book = await ApiService.instance.getBookByIsbn(widget.isbn);
      if (!mounted) return;
      setState(() {
        _book = book;
        _loadingBook = false;
        _bookError = book == null ? 'Book not found.' : null;
      });
      if (book != null) {
        _trackView(book);
        _fetchSimilar(book.title);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBook = false;
          _bookError = 'Failed to load book details.';
        });
      }
    }
  }

  Future<void> _fetchSimilar(String title) async {
    setState(() => _loadingSimilar = true);
    try {
      final recs = await context.read<BookProvider>().getRecommendations(title);
      if (mounted) setState(() => _similar = recs);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSimilar = false);
    }
  }

  void _trackView(Book book) {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    final uid = auth.currentUser!.id;
    ApiService.instance.trackActivity(userId: uid, bookName: book.title);
    SupabaseService.instance.trackActivity(userId: uid, bookName: book.title);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBook) return const _LoadingScaffold();
    if (_bookError != null || _book == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              Text(_bookError ?? 'Unknown error'),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _fetchBook, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final book = _book!;
    final auth = context.watch<AuthProvider>();
    final favs = context.watch<FavoritesProvider>();
    final isFav = favs.isFavorite(book.isbn13);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero app bar with cover ─────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: book.coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                        color: Theme.of(context).colorScheme.surface),
                    errorWidget: (_, __, ___) => Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: const Icon(Icons.menu_book_rounded, size: 80)),
                  ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Favourite toggle
              if (auth.isLoggedIn)
                IconButton(
                  icon: Icon(
                    isFav ? Icons.bookmark : Icons.bookmark_outline,
                    color: isFav ? const Color(0xFFFFD166) : Colors.white,
                  ),
                  onPressed: () {
                    final uid = auth.currentUser!.id;
                    if (favs.favorites.isEmpty) {
                      favs.loadFavorites(uid);
                    }
                    favs.toggleFavorite(userId: uid, book: book);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isFav
                          ? 'Removed from favorites'
                          : 'Added to favorites'),
                    ));
                  },
                )
              else
                IconButton(
                  icon: const Icon(Icons.bookmark_outline),
                  tooltip: 'Sign in to save',
                  onPressed: () => context.push('/login'),
                ),
            ],
          ),

          // ── Book info ───────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Title
                Text(book.title,
                    style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 6),

                // Author
                Text(book.authorsFormatted,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 14),

                // Rating + stats row
                Row(
                  children: [
                    RatingBarIndicator(
                      rating: book.averageRating.clamp(0.0, 5.0),
                      itemBuilder: (_, __) => const Icon(Icons.star,
                          color: Color(0xFFFFD166)),
                      itemCount: 5,
                      itemSize: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${book.averageRating.toStringAsFixed(1)} '
                      '(${_formatCount(book.ratingsCount)} ratings)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Meta chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (book.publishedDate.isNotEmpty)
                      _Chip(
                          icon: Icons.calendar_today_outlined,
                          label: book.publishedDate.substring(0, 4)),
                    if (book.pageCount > 0)
                      _Chip(
                          icon: Icons.menu_book_outlined,
                          label: '${book.pageCount} pages'),
                    ...book.categoryList
                        .take(3)
                        .map((c) => _Chip(icon: Icons.label_outline, label: c)),
                  ],
                ),
                const SizedBox(height: 20),

                // Description
                if (book.description.isNotEmpty) ...[
                  Text('About', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  AnimatedCrossFade(
                    firstChild: Text(
                      book.description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    secondChild: Text(
                      book.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    crossFadeState: _descExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 250),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _descExpanded = !_descExpanded),
                    child: Text(_descExpanded ? 'Show less' : 'Read more'),
                  ),
                ],

                const SizedBox(height: 16),

                // CTA
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Get Recommendations'),
                  onPressed: () => context.push(
                      '/recommend/${Uri.encodeComponent(book.title)}'),
                ),

                const SizedBox(height: 32),

                // Similar books
                if (_loadingSimilar)
                  const ShimmerGrid()
                else if (_similar.isNotEmpty) ...[
                  Text('Similar Books',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _similar.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => BookCard(book: _similar[i]),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 320,
            color: Theme.of(context).colorScheme.surface,
          ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
