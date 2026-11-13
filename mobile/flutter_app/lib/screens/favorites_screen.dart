import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';
import '../domain/entities/learning_note.dart';
import '../providers/notes_provider.dart';
import '../providers/language_provider.dart';
import '../utils/date_format.dart';
import '../theme/design_system.dart';


NotesProvider? _getNotesProvider(BuildContext context, {bool listen = false}) {
  try {
    return Provider.of<NotesProvider>(context, listen: listen);
  } catch (_) {
    return null;
  }
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _sortByTitle = false;
  final TextEditingController _notesSearchController = TextEditingController();
  String _notesSearchQuery = '';
  String? _selectedNoteTypeFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        context.read<FavoritesProvider>().loadFavorites(auth.currentUser!.id);
        _getNotesProvider(context)?.loadAllNotes(userId: auth.currentUser!.id);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final favs = context.watch<FavoritesProvider>();

    if (!auth.isLoggedIn) {
      if (favs.favorites.isNotEmpty || favs.activeUserId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          favs.clearFavorites();
          _getNotesProvider(context)?.clear();
        });
      }
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('library'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(DesignSystem.spacing32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(DesignSystem.spacing24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bookmark_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: DesignSystem.spacing24),
                Text(context.tr('favorites_title'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: DesignSystem.spacing12),
                Text(
                  context.tr('sign_in_subtitle'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                ),
                const SizedBox(height: DesignSystem.spacing32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.push('/login?redirect=/favorites'),
                    child: Text(context.tr('sign_in_hint')),
                  ),
                ),
                const SizedBox(height: DesignSystem.spacing12),
                TextButton(
                  onPressed: () => context.push('/register?redirect=/favorites'),
                  child: Text(context.tr('create_one')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (auth.currentUser != null && favs.activeUserId != auth.currentUser!.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        favs.loadFavorites(auth.currentUser!.id);
        _getNotesProvider(context)?.loadAllNotes(userId: auth.currentUser!.id);
      });
    }

    final notesProvider = _getNotesProvider(context, listen: true);
    final notesCount = notesProvider?.allNotes.length ?? 0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('library')),
          bottom: TabBar(
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bookmark_outline, size: 18),
                    const SizedBox(width: 6),
                    Text(context.tr('favorites_title')),
                    if (favs.favorites.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${favs.favorites.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                key: const Key('library_notes_tab'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_note_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(context.tr('tab_notes')),
                    if (notesCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$notesCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                await favs.retryFailedSync(auth.currentUser!.id);
                await favs.loadFavorites(auth.currentUser!.id);
              },
              child: _buildBody(auth, favs),
            ),
            _buildNotesTab(auth, notesProvider),
          ],
        ),
      ),
    );
  }

  Widget? _buildSyncBanner(BuildContext context, AuthProvider auth, FavoritesProvider favs) {
    if (favs.failedSyncCount > 0) {
      return Container(
        key: const Key('favorites_sync_failed_banner'),
        width: double.infinity,
        color: Theme.of(context).colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.sync_problem_rounded,
                size: 20, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('favorites_sync_failed'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            TextButton(
              key: const Key('favorites_retry_sync_button'),
              onPressed: () => favs.retryFailedSync(auth.currentUser!.id),
              child: Text(
                context.tr('retry'),
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }

    if (favs.pendingSyncCount > 0) {
      return Container(
        key: const Key('favorites_sync_pending_banner'),
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: favs.isSyncing
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Icon(Icons.cloud_upload_outlined,
                      size: 16, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('favorites_sync_pending',
                    args: {'count': favs.pendingSyncCount.toString()}),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (!favs.isSyncing)
              TextButton(
                key: const Key('favorites_sync_now_button'),
                onPressed: () => favs.retryFailedSync(auth.currentUser!.id),
                child: Text(context.tr('sync_now')),
              ),
          ],
        ),
      );
    }
    return null;
  }

  Widget _buildBody(AuthProvider auth, FavoritesProvider favs) {
    if (favs.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final banner = _buildSyncBanner(context, auth, favs);

    if (favs.favorites.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (banner != null) banner,
          Padding(
            padding: const EdgeInsets.all(DesignSystem.spacing32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.all(DesignSystem.spacing24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bookmark_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: DesignSystem.spacing24),
                Text(context.tr('favorites_empty_title'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: DesignSystem.spacing12),
                Text(
                  context.tr('favorites_empty_message'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                ),
                const SizedBox(height: DesignSystem.spacing32),
                ElevatedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(context.tr('explore')),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final filteredFavorites = favs.favorites.where((f) {
      if (_searchQuery.trim().isEmpty) return true;
      return f.bookTitle.toLowerCase().contains(_searchQuery.trim().toLowerCase());
    }).toList();

    if (_sortByTitle) {
      filteredFavorites.sort((a, b) => a.bookTitle.toLowerCase().compareTo(b.bookTitle.toLowerCase()));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        if (banner != null) banner,
        Padding(
          padding: const EdgeInsets.fromLTRB(DesignSystem.spacing16, DesignSystem.spacing8, DesignSystem.spacing16, DesignSystem.spacing8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: context.tr('search_hint'),
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  _sortByTitle ? Icons.sort_by_alpha_rounded : Icons.access_time_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                tooltip: _sortByTitle ? context.tr('title_a_z') : context.tr('newest'),
                onPressed: () {
                  setState(() => _sortByTitle = !_sortByTitle);
                },
              ),
            ],
          ),
        ),
        if (filteredFavorites.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignSystem.spacing32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('no_books_found'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('no_books_message'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: filteredFavorites.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 104),
              itemBuilder: (context, i) {
                final fav = filteredFavorites[i];
              final hasPending = favs.hasPendingSync(fav.isbn13);
              return Dismissible(
                key: ValueKey(fav.isbn13),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: Colors.red.withOpacity(0.8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delete_outline, color: Colors.white),
                      const SizedBox(height: 4),
                      Text(context.tr('remove'),
                          style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(context.tr('remove_favorite_title')),
                      content: Text(context.tr('remove_favorite_confirm', args: {'title': fav.bookTitle})),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.tr('cancel'))),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(context.tr('remove'),
                                style: const TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                },
                onDismissed: (_) {
                  favs.removeFavoriteByIsbn(
                    userId: auth.currentUser!.id,
                    isbn13: fav.isbn13,
                  );
                },
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing16, vertical: DesignSystem.spacing8),
                  leading: ClipRRect(
                    borderRadius: DesignSystem.borderRadiusSmall,
                    child: fav.thumbnail.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: fav.thumbnail,
                            width: 60,
                            height: 85,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                                width: 60,
                                height: 85,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest),
                            errorWidget: (_, __, ___) => Container(
                                width: 60,
                                height: 85,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.menu_book_rounded, size: 24)),
                          )
                        : Container(
                            width: 60,
                            height: 85,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.menu_book_rounded, size: 24)),
                  ),
                  title: Text(
                    fav.bookTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${context.tr('saved')}: ${context.trRelativeDate(fav.addedAt)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                        if (hasPending) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: context.tr('favorites_sync_pending', args: {'count': '1'}),
                            child: Icon(
                              Icons.cloud_upload_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                  onTap: () => context.push('/book/${fav.isbn13}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNotesTab(AuthProvider auth, NotesProvider? notesProvider) {
    if (notesProvider == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        await notesProvider.loadAllNotes(userId: auth.currentUser?.id);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                key: const Key('notes_hub_search_input'),
                controller: _notesSearchController,
                onChanged: (val) => setState(() => _notesSearchQuery = val),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: context.tr('search_notes_placeholder'),
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _notesSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _notesSearchController.clear();
                            setState(() => _notesSearchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip(
                  label: context.tr('filter_all'),
                  isSelected: _selectedNoteTypeFilter == null,
                  onSelected: () => setState(() => _selectedNoteTypeFilter = null),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: context.tr('note_type_personal_note'),
                  isSelected: _selectedNoteTypeFilter == 'personal_note',
                  onSelected: () => setState(() => _selectedNoteTypeFilter = 'personal_note'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: context.tr('note_type_key_takeaway'),
                  isSelected: _selectedNoteTypeFilter == 'key_takeaway',
                  onSelected: () => setState(() => _selectedNoteTypeFilter = 'key_takeaway'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: context.tr('note_type_question'),
                  isSelected: _selectedNoteTypeFilter == 'question',
                  onSelected: () => setState(() => _selectedNoteTypeFilter = 'question'),
                ),
                const SizedBox(width: 12),
                ActionChip(
                  key: const Key('export_notes_hub_chip'),
                  avatar: const Icon(Icons.download_rounded, size: 16),
                  label: Text(context.tr('export_notes_button')),
                  onPressed: () => _exportNotesDialog(context, notesProvider),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  key: const Key('learning_outcomes_hub_chip'),
                  avatar: const Icon(Icons.psychology_outlined, size: 16),
                  label: Text(context.tr('nav_learning')),
                  onPressed: () => context.push('/learning'),
                ),
              ],
            ),
          ),
          _buildSmartReviewBanner(context, notesProvider),
          const SizedBox(height: 8),
          Expanded(
            child: _buildNotesList(auth, notesProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    final theme = Theme.of(context);
    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) => onSelected(),
      label: Text(label),
      selectedColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildNotesList(AuthProvider auth, NotesProvider notesProvider) {
    if (notesProvider.isLoading && notesProvider.allNotes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notesProvider.allNotes.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(DesignSystem.spacing32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.all(DesignSystem.spacing24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.edit_note_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: DesignSystem.spacing24),
                Text(context.tr('tab_notes'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: DesignSystem.spacing12),
                Text(
                  context.tr('empty_notes_all'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                ),
                const SizedBox(height: DesignSystem.spacing32),
                ElevatedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(context.tr('explore')),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final query = _notesSearchQuery.trim().toLowerCase();
    final filtered = notesProvider.allNotes.where((note) {
      if (_selectedNoteTypeFilter != null && note.noteType != _selectedNoteTypeFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesContent = note.content.toLowerCase().contains(query);
        final matchesBook = note.bookId.toLowerCase().contains(query);
        return matchesContent || matchesBook;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignSystem.spacing32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
              const SizedBox(height: 16),
              Text(
                context.tr('no_books_found'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('no_books_message'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final note = filtered[index];

        Color badgeColor;
        IconData badgeIcon;
        String badgeLabel;

        switch (note.noteType) {
          case 'key_takeaway':
            badgeColor = const Color(0xFFF59E0B);
            badgeIcon = Icons.lightbulb_rounded;
            badgeLabel = context.tr('note_type_key_takeaway');
            break;
          case 'question':
            badgeColor = const Color(0xFF8B5CF6);
            badgeIcon = Icons.help_outline_rounded;
            badgeLabel = context.tr('note_type_question');
            break;
          case 'personal_note':
          default:
            badgeColor = const Color(0xFF3B82F6);
            badgeIcon = Icons.sticky_note_2_outlined;
            badgeLabel = context.tr('note_type_personal_note');
            break;
        }

        final formattedDate = formatShortDate(note.createdAt, context.read<LanguageProvider>().currentLanguageCode);

        return Container(
          key: Key('hub_note_card_${note.id}'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, size: 14, color: badgeColor),
                        const SizedBox(width: 4),
                        Text(
                          badgeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formattedDate,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                  if (note.isPendingSync) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_upload_outlined, size: 12, color: Colors.orange),
                          const SizedBox(width: 3),
                          Text(
                            context.tr('note_sync_pending'),
                            style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ] else if (note.isSyncFailed) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sync_problem_rounded, size: 12, color: Colors.red),
                          const SizedBox(width: 3),
                          Text(
                            context.tr('note_sync_failed'),
                            style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    key: Key('delete_hub_note_button_${note.id}'),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: context.tr('delete_note'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: theme.colorScheme.error.withOpacity(0.8),
                    onPressed: () => _confirmDeleteHubNote(context, notesProvider, note),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                note.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                key: Key('open_book_link_${note.id}'),
                onTap: () => context.push('/book/${note.bookId}'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book_rounded, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'ISBN: ${note.bookId}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, size: 10, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSmartReviewBanner(BuildContext context, NotesProvider notesProvider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (notesProvider.dueReviewCount == 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B2430) : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFBBF7D0),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF16A34A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('smart_review_empty'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white70 : const Color(0xFF15803D),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final topReview = notesProvider.dueReviews.first;
    final noteData = topReview['note'] is Map<String, dynamic> ? topReview['note'] as Map<String, dynamic> : null;
    final noteContent = noteData?['content']?.toString() ?? 'Learning takeaway';
    final noteId = topReview['note_id']?.toString() ?? noteData?['id']?.toString() ?? '';
    final stage = topReview['stage'] ?? 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF231C30) : const Color(0xFFFAF5FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF7C3AED).withOpacity(0.3) : const Color(0xFFE9D5FF),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_outlined, size: 20, color: Color(0xFF9333EA)),
                const SizedBox(width: 8),
                Text(
                  context.tr('smart_review_title'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF9333EA),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9333EA).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    context.tr('smart_review_due_count', args: {'count': notesProvider.dueReviewCount.toString()}),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9333EA)),
                  ),
                ),
                const Spacer(),
                Text(
                  context.tr('smart_review_stage', args: {'stage': stage.toString()}),
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              noteContent,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  key: const Key('review_struggled_button'),
                  onPressed: () => notesProvider.submitReview(noteId: noteId, outcome: 'struggled'),
                  icon: const Icon(Icons.replay_rounded, size: 14),
                  label: Text(context.tr('smart_review_struggled'), style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  key: const Key('review_remembered_button'),
                  onPressed: () => notesProvider.submitReview(noteId: noteId, outcome: 'remembered'),
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: Text(context.tr('smart_review_remembered'), style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _exportNotesDialog(BuildContext context, NotesProvider notesProvider) async {
    final md = await notesProvider.exportNotesMarkdown();
    if (!context.mounted) return;

    if (md == null || md.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('empty_notes_library'))),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('export_notes_title'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('export_notes_desc'),
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black26
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: SelectableText(
                          md,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const Key('copy_markdown_button'),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(context.tr('copy_markdown')),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: md));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('markdown_copied'))),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteHubNote(BuildContext context, NotesProvider notesProvider, LearningNote note) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.tr('delete_note')),
          content: Text(context.tr('delete_note_confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.tr('cancel')),
            ),
            ElevatedButton(
              key: const Key('confirm_delete_hub_note_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final trDeleted = context.tr('note_deleted');
                final trFailed = context.tr('update_failed');
                Navigator.of(dialogContext).pop();
                final ok = await notesProvider.removeNote(noteId: note.id, bookId: note.bookId);
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok ? trDeleted : trFailed),
                  ),
                );
              },
              child: Text(context.tr('delete')),
            ),
          ],
        );
      },
    );
  }

}
