import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/entities/book.dart';
import '../providers/language_provider.dart';
import '../application/use_cases/manage_catalog_use_case.dart';
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

  // Filters
  String? _sort = 'popularity';
  int? _minPages;
  int? _maxPages;
  double? _minRating;

  @override
  void initState() {
    super.initState();
    _fetchInitial();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchInitial() async {
    await _fetchMore();
  }

  Future<void> _applyFilters({String? sort, int? minPages, int? maxPages, double? minRating}) async {
    setState(() {
      _sort = sort ?? _sort;
      if (minPages != -1) _minPages = minPages ?? _minPages;
      if (minPages == -1) _minPages = null;
      if (maxPages != -1) _maxPages = maxPages ?? _maxPages;
      if (maxPages == -1) _maxPages = null;
      if (minRating != -1) _minRating = minRating ?? _minRating;
      if (minRating == -1) _minRating = null;

      _books.clear();
      _page = 1;
      _hasMore = true;
    });
    await _fetchMore();
  }

  Future<void> _fetchMore() async {
    if (!_hasMore || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final result = await context.read<ManageCatalogUseCase>().getBooksByCategory(
        category: widget.genre,
        page: _page,
        perPage: _perPage,
        sort: _sort,
        minPages: _minPages,
        maxPages: _maxPages,
        minRating: _minRating,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
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
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (_minPages != null || _maxPages != null || _minRating != null || _sort != 'popularity')
                  OutlinedButton.icon(
                    onPressed: () => _applyFilters(sort: 'popularity', minPages: -1, maxPages: -1, minRating: -1),
                    icon: const Icon(Icons.refresh),
                    label: Text(context.tr('reset')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(context.tr('explore_all_books')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _FilterSheet(
          initialSort: _sort ?? 'popularity',
          onApply: (sort) {
            _applyFilters(sort: sort);
          },
        );
      },
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final String initialSort;
  final Function(String) onApply;

  const _FilterSheet({required this.initialSort, required this.onApply});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _selectedSort;

  @override
  void initState() {
    super.initState();
    _selectedSort = widget.initialSort;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('sort_and_filter'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Text(context.tr('sort_by'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSortChip('popularity', context.tr('popularity')),
              _buildSortChip('rating', context.tr('rating')),
              _buildSortChip('newest', context.tr('newest')),
              _buildSortChip('oldest', context.tr('oldest')),
              _buildSortChip('title', context.tr('title_a_z')),
            ],
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              widget.onApply(_selectedSort);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(context.tr('apply_options')),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String value, String label) {
    final isSelected = _selectedSort == value;
    final colorScheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      onSelected: (selected) {
        if (selected) setState(() => _selectedSort = value);
      },
      selectedColor: colorScheme.primary.withOpacity(0.2),
      checkmarkColor: colorScheme.primary,
    );
  }
}
