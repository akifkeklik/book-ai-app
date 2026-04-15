import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book_model.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../widgets/book_card.dart';

class CategoryTimelineScreen extends StatefulWidget {
  final String genre;
  const CategoryTimelineScreen({super.key, required this.genre});

  @override
  State<CategoryTimelineScreen> createState() => _CategoryTimelineScreenState();
}

class _CategoryTimelineScreenState extends State<CategoryTimelineScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Book> _books = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  final int _perPage = 40; // Senior Update: Increased for smoother browsing

  @override
  void initState() {
    super.initState();
    _fetchInitial();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchInitial() async {
    setState(() => _isLoading = true);
    await _fetchMore();
    setState(() => _isLoading = false);
  }

  Future<void> _fetchMore() async {
    if (!_hasMore || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.instance.getBooksByCategory(
        category: widget.genre,
        page: _page,
        perPage: _perPage,
      );
      final newBooks = result['books'] as List<Book>;
      final totalPages = result['total_pages'] as int? ?? 1;
      if (!mounted) return;
      setState(() {
        _books.addAll(newBooks);
        _page++;
        if (_page > totalPages || newBooks.isEmpty) {
          _hasMore = false;
        }
      });
    } catch (e) {
      debugPrint('Error fetching category books: $e');
      if (mounted) setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _fetchMore();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.trGenre(widget.genre)),
        elevation: 0,
      ),
      body: _books.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? _buildEmptyState(theme, lang)
              : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          context.tr('scroll_to_discover'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white38),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.45,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index < _books.length) {
                              return BookCard(book: _books[index]);
                            }
                            return const Center(
                                child: CircularProgressIndicator());
                          },
                          childCount: _books.length + (_hasMore ? 1 : 0),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, LanguageProvider lang) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_stories_rounded,
                  size: 80, color: theme.colorScheme.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 32),
            Text(
              context.tr('no_books_found'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('no_books_found_desc'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.explore_outlined),
              label: Text(context.tr('explore_all_books')),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
