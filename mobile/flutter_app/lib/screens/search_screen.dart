import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/book_provider.dart';
import '../providers/language_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/shimmer_loader.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookProv = context.watch<BookProvider>();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.tr('search_placeholder'),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      context.read<BookProvider>().clearSearch();
                    },
                  )
                : null,
          ),
          onChanged: (q) {
            setState(() {});
            context.read<BookProvider>().searchDebounced(q);
          },
          onSubmitted: (q) {
            if (q.trim().length >= 2) {
              context.read<BookProvider>().search(q.trim());
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            onPressed: () => _showFilterSheet(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(bookProv),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final bookProv = context.read<BookProvider>();
    String tempAuthor = bookProv.filterAuthor;
    int tempRange = bookProv.filterPageRange; // 0: All, 1: <300, 2: 300-500, 3: >500

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
                left: 24, right: 24, top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.tr('filters'), style: Theme.of(sheetCtx).textTheme.headlineSmall),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            tempAuthor = '';
                            tempRange = 0;
                          });
                        },
                        child: Text(context.tr('reset')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Author TextField
                  Text(context.tr('author_name'), style: Theme.of(sheetCtx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: tempAuthor,
                    decoration: InputDecoration(
                      hintText: 'e.g. İlber Ortaylı',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    onChanged: (val) => tempAuthor = val,
                  ),
                  const SizedBox(height: 24),

                  // Page Count Chips
                  Text(context.tr('page_count'), style: Theme.of(sheetCtx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(context.tr('all')),
                        selected: tempRange == 0,
                        onSelected: (val) => setSheetState(() => tempRange = 0),
                      ),
                      ChoiceChip(
                        label: Text(context.tr('pages_less_than_300')),
                        selected: tempRange == 1,
                        onSelected: (val) => setSheetState(() => tempRange = 1),
                      ),
                      ChoiceChip(
                        label: Text(context.tr('pages_300_500')),
                        selected: tempRange == 2,
                        onSelected: (val) => setSheetState(() => tempRange = 2),
                      ),
                      ChoiceChip(
                        label: Text(context.tr('pages_more_than_500')),
                        selected: tempRange == 3,
                        onSelected: (val) => setSheetState(() => tempRange = 3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Apply Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        bookProv.setFilters(author: tempAuthor, pageRange: tempRange);
                        Navigator.pop(sheetCtx);
                      },
                      child: Text(context.tr('apply_filters')),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBody(BookProvider bookProv) {
    switch (bookProv.searchStatus) {
      case BookStatus.initial:
        return LibrisEmptyState(
          icon: Icons.search_outlined,
          title: context.tr('search_empty_title'),
          message: context.tr('search_empty_message'),
        );

      case BookStatus.loading:
        return const ShimmerList(count: 6);

      case BookStatus.error:
        return _ErrorState(
          message: bookProv.searchError ?? 'Search failed.',
          onRetry: () => bookProv.search(bookProv.lastQuery),
        );

      case BookStatus.loaded:
        if (bookProv.searchResults.isEmpty) {
          return const LibrisEmptyState(
            icon: Icons.sentiment_dissatisfied_outlined,
            title: 'No results',
            message: 'Try a different keyword',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          itemCount: bookProv.searchResults.length,
          itemBuilder: (_, i) => BookListTile(book: bookProv.searchResults[i]),
        );
    }
  }
}



class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
