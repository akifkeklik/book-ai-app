import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/search_provider.dart';
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
    final searchProv = context.watch<SearchProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Custom Search Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _focusNode.hasFocus
                              ? theme.colorScheme.primary.withOpacity(0.5)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Icon(
                            Icons.search_rounded,
                            color: _focusNode.hasFocus
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withOpacity(0.4),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                hintText: context.tr('search_placeholder'),
                                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (q) {
                                setState(() {});
                                context.read<SearchProvider>().searchDebounced(q);
                              },
                              onSubmitted: (q) {
                                if (q.trim().length >= 2) {
                                  context.read<SearchProvider>().search(q.trim());
                                }
                              },
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            IconButton(
                              icon: Icon(
                                Icons.cancel_rounded,
                                color: theme.colorScheme.onSurface.withOpacity(0.4),
                                size: 20,
                              ),
                              onPressed: () {
                                _controller.clear();
                                context.read<SearchProvider>().clearSearch();
                                setState(() {});
                                _focusNode.requestFocus();
                              },
                            ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Search Body ───────────────────────────────────────────────────
            Expanded(
              child: _buildBody(searchProv, theme, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SearchProvider searchProv, ThemeData theme, bool isDark) {
    switch (searchProv.status) {
      case SearchStatus.initial:
        return _buildInitialDiscoveryState(theme, isDark);

      case SearchStatus.loading:
        return const ShimmerList(count: 6);

      case SearchStatus.error:
        return _ErrorState(
          message: context.tr(searchProv.error ?? 'search_failed'),
          onRetry: () => searchProv.search(searchProv.lastQuery),
        );

      case SearchStatus.loaded:
        if (searchProv.searchResults.isEmpty) {
          return LibrisEmptyState(
            icon: Icons.sentiment_dissatisfied_outlined,
            title: context.tr('search_no_results_title'),
            message: context.tr('search_no_results_message'),
          );
        }
        return Column(
          children: [
            if (searchProv.isFromCache)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('offline_cached_results'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 0, bottom: 32),
                itemCount: searchProv.searchResults.length,
                itemBuilder: (_, i) => BookListTile(book: searchProv.searchResults[i]),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildInitialDiscoveryState(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Discovery Banner
          GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              context.push('/ai');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.8),
                    Color.lerp(theme.colorScheme.primary, Colors.black, 0.3) ?? theme.colorScheme.primary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('ai_discovery_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('ai_discovery_desc'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
          Text(
            context.tr('categories'),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              'Fiction', 'Science Fiction', 'Mystery', 'Romance', 'Fantasy', 'History', 'Biography'
            ].map((cat) => ActionChip(
              label: Text(context.trGenre(cat)),
              onPressed: () {
                FocusScope.of(context).unfocus();
                _controller.text = cat;
                context.read<SearchProvider>().search(cat);
              },
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            )).toList(),
          ),
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
              label: Text(context.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }
}
