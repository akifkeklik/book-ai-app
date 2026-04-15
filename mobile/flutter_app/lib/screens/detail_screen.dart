import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book_model.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../widgets/book_card.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.isbn, this.initialBook});
  final String isbn;
  final Book? initialBook;

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
    if (widget.initialBook != null) {
      _book = widget.initialBook;
      _loadingBook = false;

      final initial = widget.initialBook!;
      _trackView(initial);
      _fetchSimilar(initial.title);

      if (widget.isbn != '_' && widget.isbn.trim().isNotEmpty) {
        _fetchBook();
      }
      return;
    }
    _fetchBook();
  }

  Future<void> _fetchBook() async {
    final isbn = widget.isbn.trim();
    if (isbn.isEmpty || isbn == '_') {
      if (widget.initialBook != null) return;
      setState(() {
        _loadingBook = false;
        _bookError = context.tr('no_books_found');
      });
      return;
    }

    setState(() {
      _loadingBook = true;
      _bookError = null;
    });
    try {
      // 1. Try Supabase (Most reliable for 6k+ books)
      Book? book = await SupabaseService.instance.getBookByIsbn(isbn);

      // 2. Fallback to Flask Api (If Supabase fails or doesn't have it)
      book ??= await ApiService.instance.getBookByIsbn(isbn);

      if (!mounted) return;
      if (!mounted) return;
      setState(() {
        _book = book;
        _loadingBook = false;
        _bookError = book == null ? context.tr('no_books_found') : null;
      });

      if (book != null) {
        _trackView(book);
        _fetchSimilar(book.title);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBook = false;
          _bookError = context.tr('error_loading_books');
        });
      }
    }
  }

  Future<void> _fetchSimilar(String title) async {
    setState(() => _loadingSimilar = true);
    try {
      final recs = await ApiService.instance.getRecommendations(title);
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
    SupabaseService.instance.trackActivity(
      userId: uid,
      activityType: 'view',
      bookId: book.isbn13,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadingBook) return const _LoadingScaffold();

    if (_bookError != null || _book == null) {
      return Scaffold(
        appBar: AppBar(elevation: 0, backgroundColor: Colors.transparent),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: 80, color: theme.colorScheme.error.withOpacity(0.5)),
                const SizedBox(height: 24),
                Text(
                  _bookError ?? context.tr('error'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _fetchBook,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.tr('retry')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final book = _book!;
    final isFavorite =
        context.watch<FavoritesProvider>().isFavorite(book.isbn13);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(context, book, isFavorite),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, book),
                  const SizedBox(height: 24),
                  _buildStats(context, book),
                  const SizedBox(height: 32),
                  _buildActionButtons(context, book),
                  const SizedBox(height: 32),
                  _buildDescription(context, book),
                  const SizedBox(height: 40),
                  if (_similar.isNotEmpty || _loadingSimilar) ...[
                    Text(
                      context.tr('similar_books'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildSimilarList(),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, Book book, bool isFavorite) {
    final auth = context.read<AuthProvider>();
    final favs = context.read<FavoritesProvider>();

    return SliverAppBar(
      expandedHeight: 400,
      pinned: true,
      stretch: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'cover_${book.isbn13}',
              child: ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.3),
                      Theme.of(context).colorScheme.surface,
                    ],
                  ).createShader(Rect.fromLTRB(0, 0, rect.width, rect.height));
                },
                blendMode: BlendMode.darken,
                child: NetworkCoverWithFallback(
                  book: book,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        CircleAvatar(
          backgroundColor: Colors.black26,
          child: IconButton(
            icon: Icon(
              isFavorite ? Icons.bookmark : Icons.bookmark_outline,
              color: isFavorite ? const Color(0xFFFFD166) : Colors.white,
            ),
            onPressed: () {
              final uid = auth.currentUser?.id;
              if (uid == null) {
                context.push('/login');
                return;
              }
              HapticFeedback.mediumImpact();
              favs.toggleFavorite(userId: uid, book: book);
            },
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Book book) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          style: theme.textTheme.headlineLarge?.copyWith(
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          book.authorsFormatted,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStats(BuildContext context, Book book) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RatingBarIndicator(
                  rating: book.averageRating.clamp(0.0, 5.0),
                  itemBuilder: (_, __) =>
                      const Icon(Icons.star, color: Color(0xFFFFD166)),
                  itemCount: 5,
                  itemSize: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  book.averageRating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Text(
              '${_formatCount(book.ratingsCount)} ${context.tr('ratings')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const Spacer(),
        if (book.pageCount > 0) ...[
          _StatDivider(),
          _StatItem(label: context.tr('page_count'), value: book.pageCount.toString()),
        ],
        if (book.publishedDate.isNotEmpty) ...[
          _StatDivider(),
          _StatItem(label: context.tr('year'), value: book.publishedDate.split('-').first),
        ],
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, Book book) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () =>
                context.push('/recommend/${Uri.encodeComponent(book.title)}'),
            icon: const Icon(Icons.auto_awesome),
            label: Text(context.tr('ai_insight')),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(BuildContext context, Book book) {
    if (book.description.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('about'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        AnimatedCrossFade(
          firstChild: Text(
            book.description,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
          ),
          secondChild: Text(
            book.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
          ),
          crossFadeState: _descExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
        TextButton(
          onPressed: () => setState(() => _descExpanded = !_descExpanded),
          child: Text(_descExpanded ? context.tr('show_less') : context.tr('read_more')),
        ),
      ],
    );
  }

  Widget _buildSimilarList() {
    if (_loadingSimilar) {
      return const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      height: 330,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _similar.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, i) => BookCard(book: _similar[i]),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: Theme.of(context).dividerColor.withOpacity(0.2),
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
