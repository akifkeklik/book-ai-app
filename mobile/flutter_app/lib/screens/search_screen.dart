import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/book_provider.dart';
import '../widgets/book_card.dart';
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
            hintText: 'Search books, authors, genres…',
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
      ),
      body: _buildBody(bookProv),
    );
  }

  Widget _buildBody(BookProvider bookProv) {
    switch (bookProv.searchStatus) {
      case BookStatus.initial:
        return _EmptyState(
          icon: Icons.search_outlined,
          title: 'Discover Books',
          subtitle: 'Search by title, author, or genre',
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
          return _EmptyState(
            icon: Icons.sentiment_dissatisfied_outlined,
            title: 'No results',
            subtitle: 'Try a different keyword',
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey)),
        ],
      ),
    );
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
