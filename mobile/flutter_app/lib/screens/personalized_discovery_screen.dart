import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/book.dart';
import '../domain/entities/reading_journey.dart';
import '../data/models/book_dto.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/language_provider.dart';
import '../providers/recommendation_provider.dart';
import '../services/api_service.dart';
import '../theme/design_system.dart';
import '../widgets/book_card.dart';
import '../widgets/shimmer_loader.dart';

enum DiscoveryFilter { all, favorites, reading, taste }

class PersonalizedDiscoveryScreen extends StatefulWidget {
  const PersonalizedDiscoveryScreen({super.key});

  @override
  State<PersonalizedDiscoveryScreen> createState() =>
      _PersonalizedDiscoveryScreenState();
}

class _PersonalizedDiscoveryScreenState
    extends State<PersonalizedDiscoveryScreen> {
  DiscoveryFilter _selectedFilter = DiscoveryFilter.all;

  // Reading Journey State
  List<ReadingJourneyItem> _journeyItems = [];
  bool _loadingJourney = false;
  ReadingGoal _goal = const ReadingGoal(type: ReadingGoalType.weekly, target: 1);
  String _activeJourneyShelfTab = 'reading'; // 'reading' | 'want_to_read' | 'finished'
  String? _currentUserId;

  // In-flight mutations set for rapid-click prevention & optimistic updates
  final Set<String> _pendingInteractions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadIfNeeded();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.id;
    if (uid != _currentUserId) {
      _currentUserId = uid;
      if (uid != null) {
        _loadGoal(uid);
        _loadJourneyItems(uid);
      } else {
        setState(() {
          _journeyItems = [];
          _goal = const ReadingGoal(type: ReadingGoalType.weekly, target: 1);
        });
      }
    }
  }

  Future<void> _loadGoal(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('libris_reading_goal_$userId');
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _goal = ReadingGoal.fromJson(map);
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _goal = const ReadingGoal(type: ReadingGoalType.weekly, target: 1);
      });
    }
  }

  Future<void> _saveGoal(String userId, ReadingGoal nextGoal) async {
    setState(() => _goal = nextGoal);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'libris_reading_goal_$userId',
        jsonEncode(nextGoal.toJson()),
      );
    } catch (_) {}
  }

  Future<void> _loadJourneyItems(String userId) async {
    setState(() => _loadingJourney = true);
    try {
      // Resolve localized fallbacks before the async gap.
      final unknownAuthor = context.tr('ui_unknown_author', listen: false);
      final bookFallback = context.tr('ui_book_fallback', listen: false);
      final rawItems = await ApiService.instance.getLibrary();
      final items = <ReadingJourneyItem>[];

      for (final raw in rawItems) {
        final bid = raw['book_id']?.toString() ?? raw['id']?.toString() ?? '';
        final status = raw['status']?.toString() ?? '';
        final isFav = raw['is_favorite'] == true;
        final rawBook = raw['book'] as Map<String, dynamic>?;

        if (bid.isNotEmpty &&
            (status == 'want_to_read' ||
                status == 'reading' ||
                status == 'finished')) {
          final book = rawBook != null
              ? BookDto.fromJson(rawBook)
              : Book(
                  isbn13: bid,
                  title: bookFallback.replaceAll('{id}', bid),
                  authors: unknownAuthor,
                  categories: '',
                  description: '',
                  thumbnail: '',
                  averageRating: 0,
                  ratingsCount: 0,
                  publishedDate: '',
                  pageCount: 0,
                );
          items.add(ReadingJourneyItem(
            bookId: bid,
            status: status,
            isFavorite: isFav,
            book: book,
          ));
        }
      }

      // Overlay any pending offline outbox items for this user
      if (mounted) {
        final recs = context.read<RecommendationProvider>();
        final pending = recs.getPendingInteractions(userId);
        for (final p in pending) {
          if (p.interaction == 'clear' || p.interaction == 'remove') {
            items.removeWhere((i) => i.bookId == p.isbn13);
          } else if (p.interaction == 'want_to_read' ||
              p.interaction == 'reading' ||
              p.interaction == 'finished') {
            final existingIdx = items.indexWhere((i) => i.bookId == p.isbn13);
            if (existingIdx != -1) {
              items[existingIdx] =
                  items[existingIdx].copyWith(status: p.interaction);
            } else {
              final candidateBook = recs.personalizedRecs
                  .where((b) => b.isbn13 == p.isbn13)
                  .firstOrNull;
              if (candidateBook != null) {
                items.insert(
                  0,
                  ReadingJourneyItem(
                    bookId: p.isbn13,
                    status: p.interaction,
                    book: candidateBook,
                  ),
                );
              }
            }
          }
        }
      }

      if (mounted && context.read<AuthProvider>().currentUser?.id == userId) {
        setState(() {
          _journeyItems = items;
          _loadingJourney = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingJourney = false);
    }
  }

  void _loadIfNeeded() {
    final auth = context.read<AuthProvider>();
    final recs = context.read<RecommendationProvider>();
    final catalog = context.read<CatalogProvider>();
    final uid = auth.currentUser?.id;
    if (uid != null &&
        recs.status == RecommendationStatus.initial &&
        recs.personalizedRecs.isEmpty) {
      recs.fetchPersonalizedRecs(uid, catalog.popularBooks);
      _loadJourneyItems(uid);
      _loadGoal(uid);
    }
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    final recs = context.read<RecommendationProvider>();
    final catalog = context.read<CatalogProvider>();
    final uid = auth.currentUser?.id;
    if (uid != null) {
      await Future.wait([
        recs.fetchPersonalizedRecs(uid, catalog.popularBooks, force: true),
        _loadJourneyItems(uid),
      ]);
    }
  }

  // ── One-touch Reading Shelf Update with Rollback & Deduplication ─────────────

  Future<void> _updateReadingStatus(Book book, String newStatus) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.id;
    if (uid == null) {
      context.push('/login');
      return;
    }

    final bookId = book.isbn13;
    if (_pendingInteractions.contains(bookId)) return;

    HapticFeedback.lightImpact();
    setState(() {
      _pendingInteractions.add(bookId);
    });

    final previousItems = List<ReadingJourneyItem>.from(_journeyItems);

    // Optimistic UI update
    setState(() {
      if (newStatus == 'clear' || newStatus == 'remove') {
        _journeyItems.removeWhere((i) => i.bookId == bookId);
      } else {
        final existingIdx = _journeyItems.indexWhere((i) => i.bookId == bookId);
        if (existingIdx != -1) {
          _journeyItems[existingIdx] =
              _journeyItems[existingIdx].copyWith(status: newStatus);
        } else {
          _journeyItems.insert(
            0,
            ReadingJourneyItem(
              bookId: bookId,
              status: newStatus,
              isFavorite: context.read<FavoritesProvider>().isFavorite(bookId),
              book: book,
              addedAt: DateTime.now(),
            ),
          );
        }
      }
    });

    try {
      final success = await context.read<RecommendationProvider>().submitFeedback(
            userId: uid,
            bookId: bookId,
            interaction: newStatus,
          );

      if (!mounted) return;
      if (!success) {
        // Rollback on failure
        setState(() {
          _journeyItems = previousItems;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('update_failed')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _journeyItems = previousItems;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('update_failed')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingInteractions.remove(bookId);
        });
      }
    }
  }

  DiscoveryFilter _classifyBook(Book book) {
    final reason =
        (book.recommendationReason ?? book.explanation ?? '').toLowerCase();
    if (reason.contains('favorite') ||
        reason.contains('favorited') ||
        reason.contains('favori')) {
      return DiscoveryFilter.favorites;
    }
    if (reason.contains('read') ||
        reason.contains('reading') ||
        reason.contains('okuma') ||
        reason.contains('okudu') ||
        reason.contains('gelesen')) {
      return DiscoveryFilter.reading;
    }
    if (reason.contains('enjoy') ||
        reason.contains('genre') ||
        reason.contains('taste') ||
        reason.contains('author') ||
        reason.contains('tür') ||
        reason.contains('yazar') ||
        reason.contains('zevk') ||
        reason.contains('geschmack')) {
      return DiscoveryFilter.taste;
    }
    return DiscoveryFilter.all;
  }

  List<Book> _getFilteredBooks(List<Book> books) {
    if (_selectedFilter == DiscoveryFilter.all) return books;
    return books.where((b) {
      final category = _classifyBook(b);
      return category == _selectedFilter;
    }).toList();
  }

  Future<void> _handleDismiss(Book book) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.id;
    if (uid == null) return;

    final bookId = book.isbn13;
    if (_pendingInteractions.contains(bookId)) return;

    HapticFeedback.lightImpact();
    setState(() => _pendingInteractions.add(bookId));

    final recs = context.read<RecommendationProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await recs.submitFeedback(
        userId: uid,
        bookId: book.isbn13,
        interaction: 'dislike',
      );

      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.thumb_down_alt_outlined,
                  color: Colors.white, size: 18),
              const SizedBox(width: DesignSystem.spacing8),
              Expanded(child: Text(context.tr('recommendation_dismissed'))),
            ],
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _pendingInteractions.remove(bookId));
    }
  }

  // ── Goal Edit Dialog ────────────────────────────────────────────────────────

  void _showGoalDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.id;
    if (uid == null) return;

    ReadingGoalType selectedType = _goal.type;
    int target = _goal.target;
    String category = _goal.category ?? '';
    final controller = TextEditingController(text: target.toString());
    final catController = TextEditingController(text: category);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(context.tr('reading_goal')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('select_goal_type'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ReadingGoalType>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: ReadingGoalType.weekly,
                          child: Text(context.tr('reading_goal_weekly')),
                        ),
                        DropdownMenuItem(
                          value: ReadingGoalType.annual,
                          child: Text(context.tr('reading_goal_annual')),
                        ),
                        DropdownMenuItem(
                          value: ReadingGoalType.category,
                          child: Text(context.tr('reading_goal_category')),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedType = val;
                            if (val == ReadingGoalType.weekly && target > 10) {
                              target = 1;
                              controller.text = '1';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.tr('number_of_books'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (val) {
                        final p = int.tryParse(val);
                        if (p != null) target = p;
                      },
                    ),
                    if (selectedType == ReadingGoalType.category) ...[
                      const SizedBox(height: 14),
                      Text(
                        context.tr('ui_category_genre'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: catController,
                        decoration: InputDecoration(
                          hintText: context.tr('ui_category_hint'),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (val) => category = val,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.tr('local_goal_badge'),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(context.tr('cancel')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final p = int.tryParse(controller.text) ?? 1;
                    final safeT = p.clamp(1, 500);
                    final nextGoal = ReadingGoal(
                      type: selectedType,
                      target: safeT,
                      category: selectedType == ReadingGoalType.category &&
                              category.trim().isNotEmpty
                          ? category.trim()
                          : null,
                    );
                    _saveGoal(uid, nextGoal);
                    Navigator.pop(dialogContext);
                  },
                  child: Text(context.tr('save_goal')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openShelfSheet(BuildContext context, Book book) {
    final auth = context.read<AuthProvider>();
    final favs = context.read<FavoritesProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final uid = auth.currentUser?.id;

    final currentJourneyItem = _journeyItems
        .where((i) => i.bookId == book.isbn13)
        .firstOrNull;
    final currentStatus = currentJourneyItem?.status;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? DesignSystem.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isFav = favs.isFavorite(book.isbn13);
            return SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (book.authors.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        book.authors,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white60 : Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _buildSheetTile(
                      context: context,
                      icon: isFav ? Icons.favorite : Icons.favorite_border,
                      title: isFav
                          ? context.tr('unfavorite')
                          : context.tr('add_to_favorites'),
                      color: DesignSystem.statusFavorite,
                      isSelected: isFav,
                      onTap: () {
                        if (uid == null) {
                          Navigator.pop(sheetContext);
                          context.push('/login');
                          return;
                        }
                        favs.toggleFavorite(userId: uid, book: book);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSheetTile(
                      context: context,
                      icon: Icons.auto_stories_rounded,
                      title: context.tr('reading'),
                      color: DesignSystem.statusReading,
                      isSelected: currentStatus == 'reading',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _updateReadingStatus(book, 'reading');
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSheetTile(
                      context: context,
                      icon: Icons.bookmark_add_rounded,
                      title: context.tr('want_to_read'),
                      color: DesignSystem.statusWantToRead,
                      isSelected: currentStatus == 'want_to_read',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _updateReadingStatus(book, 'want_to_read');
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSheetTile(
                      context: context,
                      icon: Icons.check_circle_rounded,
                      title: context.tr('finished'),
                      color: DesignSystem.statusFinished,
                      isSelected: currentStatus == 'finished',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _updateReadingStatus(book, 'finished');
                      },
                    ),
                    if (currentStatus != null) ...[
                      const SizedBox(height: 8),
                      _buildSheetTile(
                        context: context,
                        icon: Icons.delete_outline_rounded,
                        title: context.tr('remove_from_shelf'),
                        color: Colors.redAccent,
                        isSelected: false,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _updateReadingStatus(book, 'clear');
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.12)
                : (isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.black.withOpacity(0.02)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color.withOpacity(0.4) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: isSelected
                      ? color
                      : (isDark ? Colors.white70 : Colors.black54),
                  size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? color : null,
                  ),
                ),
              ),
              if (isSelected) Icon(Icons.check, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reading Journey Widget Section ──────────────────────────────────────────

  Widget _buildReadingJourneyHeader(
      BuildContext context, RecommendationProvider recs) {
    if (_loadingJourney && _journeyItems.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(DesignSystem.spacing16),
        padding: const EdgeInsets.all(DesignSystem.spacing16),
        child: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final stats = calculateReadingJourney(
      items: _journeyItems,
      goal: _goal,
    );

    final nextBook = determineNextBook(recs.personalizedRecs, _journeyItems);

    final goalDescription = _goal.type == ReadingGoalType.weekly
        ? context.tr('goal_books_per_week', args: {'count': _goal.target.toString()})
        : (_goal.type == ReadingGoalType.category && _goal.category != null
            ? context.tr('goal_books_in_genre', args: {
                'count': _goal.target.toString(),
                'genre': _goal.category!,
              })
            : context.tr('goal_books_per_year', args: {'count': _goal.target.toString()}));

    return Container(
      margin: const EdgeInsets.all(DesignSystem.spacing16),
      padding: const EdgeInsets.all(DesignSystem.spacing16),
      decoration: BoxDecoration(
        color: isDark ? DesignSystem.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusLarge),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title, goal pill, local badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.emoji_events_rounded,
                    size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('reading_journey_title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            context.tr('local_goal_badge'),
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showGoalDialog(context),
                icon: const Icon(Icons.track_changes_rounded, size: 14),
                label: Text(
                  goalDescription,
                  style: const TextStyle(fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress Bar and Milestone counts
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacing12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.03)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          context.tr('books_progress', args: {
                            'completed': stats.completedCount.toString(),
                            'target': stats.safeGoal.toString(),
                          }),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (stats.isGoalReached) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: DesignSystem.statusFinished.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    size: 11, color: DesignSystem.statusFinished),
                                const SizedBox(width: 3),
                                Text(
                                  context.tr('goal_achieved'),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: DesignSystem.statusFinished,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${stats.progressPercent}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Accessible Linear Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (stats.progressPercent / 100.0).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      stats.isGoalReached
                          ? DesignSystem.statusFinished
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Subcounters
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatPill(
                      context,
                      label: context.tr('tab_finished'),
                      count: stats.completedCount,
                      color: DesignSystem.statusFinished,
                    ),
                    _buildStatPill(
                      context,
                      label: context.tr('tab_currently_reading'),
                      count: stats.readingCount,
                      color: DesignSystem.statusReading,
                    ),
                    _buildStatPill(
                      context,
                      label: context.tr('tab_want_to_read'),
                      count: stats.wantToReadCount,
                      color: DesignSystem.statusWantToRead,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Next Book Spotlight Card (Sonraki Kitap)
          if (nextBook != null) ...[
            _buildNextBookCard(context, nextBook),
            const SizedBox(height: 14),
          ],

          // Reading Shelves Segmented Tabs
          Row(
            children: [
              _buildJourneyTabButton(
                label: context.tr('tab_currently_reading'),
                count: stats.readingCount,
                keyTab: 'reading',
                icon: Icons.auto_stories_rounded,
                color: DesignSystem.statusReading,
              ),
              const SizedBox(width: 6),
              _buildJourneyTabButton(
                label: context.tr('tab_want_to_read'),
                count: stats.wantToReadCount,
                keyTab: 'want_to_read',
                icon: Icons.bookmark_add_rounded,
                color: DesignSystem.statusWantToRead,
              ),
              const SizedBox(width: 6),
              _buildJourneyTabButton(
                label: context.tr('tab_finished'),
                count: stats.completedCount,
                keyTab: 'finished',
                icon: Icons.check_circle_rounded,
                color: DesignSystem.statusFinished,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Shelf Content List / Empty state
          _buildShelfContent(context, stats),
        ],
      ),
    );
  }

  Widget _buildStatPill(BuildContext context,
      {required String label, required int count, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildNextBookCard(BuildContext context, Book nextBook) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final reason = (nextBook.recommendationReason ?? nextBook.explanation);

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacing12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 50,
              height: 72,
              child: nextBook.thumbnail.isNotEmpty
                  ? Image.network(
                      nextBook.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholderCover(),
                    )
                  : _buildPlaceholderCover(),
            ),
          ),
          const SizedBox(width: 12),
          // Details & 1-tap Actions
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 12, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('next_book_to_read'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${context.tr('next_book_to_read')}: ${nextBook.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  nextBook.authors.isEmpty ? context.tr('ui_unknown') : nextBook.authors,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${context.tr('recommended_for_you')} • ${BookCard.localizeReason(context, reason)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () =>
                          _updateReadingStatus(nextBook, 'reading'),
                      icon: const Icon(Icons.play_arrow_rounded, size: 14),
                      label: Text(
                        context.tr('start_reading'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _updateReadingStatus(nextBook, 'want_to_read'),
                      icon: const Icon(Icons.bookmark_add_rounded, size: 14),
                      label: Text(
                        context.tr('add_to_want_to_read'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneyTabButton({
    required String label,
    required int count,
    required String keyTab,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _activeJourneyShelfTab == keyTab;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Material(
        color: isSelected
            ? color.withOpacity(0.18)
            : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _activeJourneyShelfTab = keyTab),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? color.withOpacity(0.5) : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
                const SizedBox(height: 3),
                Text(
                  '$label ($count)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? color : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShelfContent(BuildContext context, ReadingJourneyStats stats) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final currentItems = _activeJourneyShelfTab == 'reading'
        ? stats.readingBooks
        : (_activeJourneyShelfTab == 'want_to_read'
            ? stats.wantToReadBooks
            : stats.completedBooks);

    if (currentItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.01),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Column(
          children: [
            Text(
              _journeyItems.isEmpty
                  ? context.tr('empty_journey_title')
                  : (_activeJourneyShelfTab == 'reading'
                      ? context.tr('ui_shelf_empty_reading')
                      : (_activeJourneyShelfTab == 'want_to_read'
                          ? context.tr('ui_shelf_empty_want')
                          : context.tr('ui_shelf_empty_finished'))),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _journeyItems.isEmpty
                  ? context.tr('empty_journey_desc')
                  : context.tr('ui_shelf_empty_hint'),
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: currentItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, idx) {
          final item = currentItems[idx];
          return _buildShelfItemCard(context, item);
        },
      ),
    );
  }

  Widget _buildShelfItemCard(BuildContext context, ReadingJourneyItem item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final book = item.book;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? DesignSystem.surfaceDarkHighlight : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 44,
              height: 64,
              child: book.thumbnail.isNotEmpty
                  ? Image.network(
                      book.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholderCover(),
                    )
                  : _buildPlaceholderCover(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  book.authors.isEmpty ? context.tr('ui_unknown') : book.authors,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const Spacer(),
                // 1-touch actions row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_activeJourneyShelfTab == 'want_to_read')
                      InkWell(
                        onTap: () => _updateReadingStatus(book, 'reading'),
                        child: Text(
                          context.tr('start_reading'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      )
                    else if (_activeJourneyShelfTab == 'reading')
                      InkWell(
                        onTap: () => _updateReadingStatus(book, 'finished'),
                        child: Text(
                          context.tr('mark_as_finished_action'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: DesignSystem.statusFinished,
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: () => _updateReadingStatus(book, 'reading'),
                        child: Text(
                          context.tr('re_read'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    InkWell(
                      onTap: () => _updateReadingStatus(book, 'clear'),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 15,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Main Build Method ───────────────────────────────────────────────────────

  Future<void> _handleResetPersonalization() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('reset_personalization')),
        content: Text(context.tr('reset_personalization_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              context.tr('reset_personalization'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final uid = context.read<AuthProvider>().currentUser?.id;
    if (uid != null) {
      final recs = context.read<RecommendationProvider>();
      final messenger = ScaffoldMessenger.of(context);
      final successMsg = context.tr('reset_personalization_success');
      final ok = await recs.resetPersonalization(uid);
      if (ok && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(successMsg)),
        );
      }
    }
  }

  Widget _buildColdStartBanner(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: DesignSystem.spacing16,
        vertical: DesignSystem.spacing8,
      ),
      padding: const EdgeInsets.all(DesignSystem.spacing16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(DesignSystem.radiusMedium),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.explore_outlined,
                color: theme.colorScheme.primary, size: 24),
          ),
          const SizedBox(width: DesignSystem.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      context.tr('cold_start_banner_title'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        context.tr('evidence_cold_start'),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('cold_start_banner_desc'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? DesignSystem.textDarkSecondary
                        : DesignSystem.textLightSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('personalized_discovery_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              context.tr('personalized_discovery_subtitle'),
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? DesignSystem.textDarkSecondary
                    : DesignSystem.textLightSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.watch<RecommendationProvider>().excludeCompleted
                ? context.tr('show_completed_books')
                : context.tr('hide_completed_books'),
            icon: Icon(
              context.watch<RecommendationProvider>().excludeCompleted
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
            onPressed: () {
              final auth = context.read<AuthProvider>();
              final uid = auth.currentUser?.id;
              if (uid != null) {
                context.read<RecommendationProvider>().toggleExcludeCompleted(uid);
              }
            },
          ),
          IconButton(
            tooltip: context.tr('reset_personalization'),
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _handleResetPersonalization,
          ),
          IconButton(
            tooltip: context.tr('retry'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Consumer2<RecommendationProvider, FavoritesProvider>(
        builder: (context, recs, favs, _) {
          final auth = context.watch<AuthProvider>();
          if (!auth.isLoggedIn) {
            return _buildUnauthenticatedState();
          }

          if (recs.status == RecommendationStatus.loading &&
              recs.personalizedRecs.isEmpty) {
            return _buildLoadingGrid();
          }

          if (recs.status == RecommendationStatus.error &&
              recs.personalizedRecs.isEmpty) {
            return _buildErrorState();
          }

          final allRecs = recs.personalizedRecs;
          if (allRecs.isEmpty) {
            return _buildEmptyState();
          }

          final filteredRecs = _getFilteredBooks(allRecs);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              slivers: [
                // Top: Reading Journey Section
                SliverToBoxAdapter(
                  child: _buildReadingJourneyHeader(context, recs),
                ),

                // Cold Start Guidance Banner
                if (recs.isColdStart || (allRecs.isNotEmpty && allRecs.first.isColdStart == true))
                  SliverToBoxAdapter(
                    child: _buildColdStartBanner(context),
                  ),

                // Filter chips & Counter
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignSystem.spacing16,
                          vertical: DesignSystem.spacing8,
                        ),
                        child: Row(
                          children: [
                            _buildFilterChip(
                              label: context.tr('filter_all'),
                              filter: DiscoveryFilter.all,
                              count: allRecs.length,
                            ),
                            const SizedBox(width: DesignSystem.spacing8),
                            _buildFilterChip(
                              label: context.tr('filter_favorites'),
                              filter: DiscoveryFilter.favorites,
                              count: allRecs
                                  .where((b) =>
                                      _classifyBook(b) == DiscoveryFilter.favorites)
                                  .length,
                            ),
                            const SizedBox(width: DesignSystem.spacing8),
                            _buildFilterChip(
                              label: context.tr('filter_reading'),
                              filter: DiscoveryFilter.reading,
                              count: allRecs
                                  .where((b) =>
                                      _classifyBook(b) == DiscoveryFilter.reading)
                                  .length,
                            ),
                            const SizedBox(width: DesignSystem.spacing8),
                            _buildFilterChip(
                              label: context.tr('filter_taste'),
                              filter: DiscoveryFilter.taste,
                              count: allRecs
                                  .where((b) =>
                                      _classifyBook(b) == DiscoveryFilter.taste)
                                  .length,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignSystem.spacing16,
                          vertical: DesignSystem.spacing4,
                        ),
                        child: Row(
                          children: [
                            Text(
                              context.tr('active_recommendations_count',
                                  args: {'count': filteredRecs.length.toString()}),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? DesignSystem.textDarkSecondary
                                    : DesignSystem.textLightSecondary,
                              ),
                            ),
                            const Spacer(),
                            if (_selectedFilter != DiscoveryFilter.all)
                              TextButton(
                                onPressed: () {
                                  setState(
                                      () => _selectedFilter = DiscoveryFilter.all);
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  context.tr('reset_filters'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: DesignSystem.spacing8),
                    ],
                  ),
                ),

                if (filteredRecs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(DesignSystem.spacing24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.filter_list_off_rounded,
                                size: 56,
                                color: isDark
                                    ? DesignSystem.textDarkSecondary.withOpacity(0.6)
                                    : DesignSystem.textLightSecondary.withOpacity(0.6)),
                            const SizedBox(height: DesignSystem.spacing16),
                            Text(
                              context.tr('empty_personalized_title'),
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: DesignSystem.spacing8),
                            TextButton.icon(
                              onPressed: () => setState(
                                  () => _selectedFilter = DiscoveryFilter.all),
                              icon: const Icon(Icons.clear_all_rounded, size: 18),
                              label: Text(context.tr('reset_filters')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignSystem.spacing16,
                      vertical: DesignSystem.spacing8,
                    ),
                    sliver: _buildGrid(filteredRecs, favs),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required DiscoveryFilter filter,
    required int count,
  }) {
    final isSelected = _selectedFilter == filter;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FilterChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected
            ? Colors.white
            : (isDark
                ? DesignSystem.textDarkPrimary
                : DesignSystem.textLightPrimary),
      ),
      backgroundColor: isDark ? DesignSystem.surfaceDark : Colors.grey.shade100,
      selectedColor: theme.colorScheme.primary,
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : (isDark ? Colors.white10 : Colors.black12),
        ),
      ),
      onSelected: (_) {
        setState(() => _selectedFilter = filter);
      },
    );
  }

  Widget _buildGrid(List<Book> books, FavoritesProvider favs) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final responsiveAspectRatio = textScale > 1.0
        ? (0.44 / (1.0 + (textScale - 1.0) * 0.7)).clamp(0.34, 0.44)
        : 0.44;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: responsiveAspectRatio,
        crossAxisSpacing: DesignSystem.spacing16,
        mainAxisSpacing: DesignSystem.spacing20,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final book = books[index];
          final isFavorite = favs.isFavorite(book.isbn13);
          final journeyStatus = _journeyItems
              .where((i) => i.bookId == book.isbn13)
              .firstOrNull
              ?.status;
          return _buildBookTile(book, isFavorite, journeyStatus);
        },
        childCount: books.length,
      ),
    );
  }

  Widget _buildBookTile(Book book, bool isFavorite, String? journeyStatus) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasReason = (book.recommendationReason ?? book.explanation) != null &&
        (book.recommendationReason ?? book.explanation)!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/book/${book.isbn13}'),
        borderRadius: BorderRadius.circular(DesignSystem.radiusMedium),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? DesignSystem.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(DesignSystem.radiusMedium),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover with badge & quick actions
              Expanded(
                flex: 12,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(DesignSystem.radiusMedium),
                      ),
                      child: book.thumbnail.isNotEmpty
                          ? Image.network(
                              book.thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildPlaceholderCover(),
                            )
                          : _buildPlaceholderCover(),
                    ),
                    // Action controls overlay (favorite + dismiss)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCircleIconButton(
                            icon: isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: isFavorite
                                ? DesignSystem.statusFavorite
                                : Colors.white,
                            backgroundColor: Colors.black45,
                            tooltip: isFavorite
                                ? context.tr('unfavorite')
                                : context.tr('add_to_favorites'),
                            onPressed: () {
                              final auth = context.read<AuthProvider>();
                              final uid = auth.currentUser?.id;
                              if (uid != null) {
                                context.read<FavoritesProvider>().toggleFavorite(
                                      userId: uid,
                                      book: book,
                                    );
                              } else {
                                context.push('/login');
                              }
                            },
                          ),
                          const SizedBox(height: 6),
                          _buildCircleIconButton(
                            icon: Icons.thumb_down_alt_outlined,
                            color: Colors.white,
                            backgroundColor: Colors.black45,
                            tooltip: context.tr('dismiss_recommendation'),
                            onPressed: () => _handleDismiss(book),
                          ),
                        ],
                      ),
                    ),
                    // Status Badge overlay if already in reading journey
                    if (journeyStatus != null)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: journeyStatus == 'reading'
                                ? DesignSystem.statusReading
                                : (journeyStatus == 'finished'
                                    ? DesignSystem.statusFinished
                                    : DesignSystem.statusWantToRead),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            journeyStatus == 'reading'
                                ? context.tr('status_reading')
                                : (journeyStatus == 'finished'
                                    ? context.tr('status_finished')
                                    : context.tr('status_want_to_read')),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // 1-touch quick action button
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: _buildCircleIconButton(
                        icon: journeyStatus == 'reading'
                            ? Icons.check_circle_rounded
                            : (journeyStatus == 'finished'
                                ? Icons.replay_rounded
                                : Icons.play_arrow_rounded),
                        color: Colors.white,
                        backgroundColor: journeyStatus == 'reading'
                            ? DesignSystem.statusFinished.withOpacity(0.9)
                            : (journeyStatus == 'finished'
                                ? DesignSystem.statusFinished.withOpacity(0.9)
                                : theme.colorScheme.primary.withOpacity(0.85)),
                        tooltip: journeyStatus == 'reading'
                            ? context.tr('mark_as_finished_action')
                            : (journeyStatus == 'finished'
                                ? context.tr('re_read')
                                : context.tr('start_reading')),
                        onPressed: () {
                          if (journeyStatus == 'reading') {
                            _updateReadingStatus(book, 'finished');
                          } else {
                            _updateReadingStatus(book, 'reading');
                          }
                        },
                      ),
                    ),
                    // Shelf action button
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: _buildCircleIconButton(
                        icon: Icons.bookmark_add_rounded,
                        color: Colors.white,
                        backgroundColor:
                            theme.colorScheme.primary.withOpacity(0.85),
                        tooltip: context.tr('manage_shelf'),
                        onPressed: () => _openShelfSheet(context, book),
                      ),
                    ),
                  ],
                ),
              ),
              // Meta info
              Expanded(
                flex: 9,
                child: Padding(
                  padding: const EdgeInsets.all(DesignSystem.spacing12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Explanation type badge
                      if (book.explanationType != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          margin: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            context.tr('exp_type_${book.explanationType}'),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                      // Rationale pill
                      if (hasReason) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 11, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  BookCard.localizeReason(
                                    context,
                                    book.recommendationReason ??
                                        book.explanation!,
                                  ),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: DesignSystem.spacing4),
                      ],
                      // Title
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Authors
                      Text(
                        book.authors.isEmpty ? context.tr('ui_unknown') : book.authors,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      // Rating & score
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 15, color: DesignSystem.rating),
                          const SizedBox(width: 3),
                          Text(
                            book.averageRating > 0
                                ? book.averageRating.toStringAsFixed(1)
                                : '—',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (book.ratingsCount > 0) ...[
                            const SizedBox(width: 2),
                            Text(
                              '(${book.ratingsCount})',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleIconButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: color, size: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderCover() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? DesignSystem.surfaceDarkHighlight : Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.book_rounded,
          size: 36,
          color: isDark ? Colors.white24 : Colors.black26,
        ),
      ),
    );
  }

  Widget _buildLoadingGrid() {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final responsiveAspectRatio = textScale > 1.0
        ? (0.44 / (1.0 + (textScale - 1.0) * 0.7)).clamp(0.34, 0.44)
        : 0.44;

    return GridView.builder(
      padding: const EdgeInsets.all(DesignSystem.spacing16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: responsiveAspectRatio,
        crossAxisSpacing: DesignSystem.spacing16,
        mainAxisSpacing: DesignSystem.spacing20,
      ),
      itemCount: 8,
      itemBuilder: (_, __) => const ShimmerBookCard(),
    );
  }

  Widget _buildErrorState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignSystem.spacing24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 64, color: theme.colorScheme.error),
            const SizedBox(height: DesignSystem.spacing16),
            Text(
              context.tr('error_loading_books'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: DesignSystem.spacing16),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignSystem.spacing32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(DesignSystem.spacing24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: DesignSystem.spacing24),
            Text(
              context.tr('empty_personalized_title'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignSystem.spacing12),
            Text(
              context.tr('empty_personalized_desc'),
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? DesignSystem.textDarkSecondary
                    : DesignSystem.textLightSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignSystem.spacing24),
            ElevatedButton.icon(
              onPressed: () {
                context.push('/categories');
              },
              icon: const Icon(Icons.explore_rounded),
              label: Text(context.tr('explore_catalog_cta')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnauthenticatedState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignSystem.spacing32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(DesignSystem.spacing24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: DesignSystem.spacing24),
            Text(
              context.tr('login_required_personalized_title'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignSystem.spacing12),
            Text(
              context.tr('login_required_personalized_desc'),
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? DesignSystem.textDarkSecondary
                    : DesignSystem.textLightSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignSystem.spacing24),
            Wrap(
              spacing: DesignSystem.spacing12,
              runSpacing: DesignSystem.spacing12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    context.push('/login');
                  },
                  icon: const Icon(Icons.login_rounded),
                  label: Text(context.tr('sign_in_to_continue')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    context.push('/categories');
                  },
                  icon: const Icon(Icons.explore_rounded),
                  label: Text(context.tr('explore_catalog_cta')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
