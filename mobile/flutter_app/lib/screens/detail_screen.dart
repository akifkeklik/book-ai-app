import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/entities/book.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/language_provider.dart';
import '../utils/date_format.dart';
import '../providers/recommendation_provider.dart';
import '../application/use_cases/view_book_details_use_case.dart';
import '../application/use_cases/manage_recommendations_use_case.dart';

import '../domain/entities/learning_note.dart';
import '../providers/notes_provider.dart';
import '../widgets/book_card.dart';
import '../theme/design_system.dart';


NotesProvider? _getNotesProvider(BuildContext context, {bool listen = false}) {
  try {
    return Provider.of<NotesProvider>(context, listen: listen);
  } catch (_) {
    return null;
  }
}

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
  String? _activeInteraction;
  String? _loadedInteractionUserId;
  static final Map<String, Color> _ambianceColorCache = {};

  Color _resolveCoverAmbiance(Book book, Brightness brightness) {
    if (_ambianceColorCache.containsKey(book.isbn13)) {
      return _ambianceColorCache[book.isbn13]!;
    }
    final cat = book.categories.toLowerCase();
    Color base;
    if (cat.contains('fiction') || cat.contains('dystopian')) {
      base = const Color(0xFF6366F1);
    } else if (cat.contains('sci') || cat.contains('tech')) {
      base = const Color(0xFF0EA5E9);
    } else if (cat.contains('history') || cat.contains('biography')) {
      base = const Color(0xFFD97706);
    } else if (cat.contains('philosophy') || cat.contains('psychology')) {
      base = const Color(0xFF8B5CF6);
    } else if (cat.contains('art') || cat.contains('poetry')) {
      base = const Color(0xFFEC4899);
    } else {
      final hash = book.title.codeUnits.fold(0, (acc, c) => (acc * 31 + c) & 0xFFFFFF);
      final hues = [const Color(0xFF3B82F6), const Color(0xFF10B981), const Color(0xFF8B5CF6), const Color(0xFFF59E0B)];
      base = hues[hash % hues.length];
    }
    final color = brightness == Brightness.dark ? base.withOpacity(0.35) : base.withOpacity(0.18);
    if (_ambianceColorCache.length > 250) {
      _ambianceColorCache.clear();
    }
    _ambianceColorCache[book.isbn13] = color;
    return color;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialBook != null) {
      _book = widget.initialBook;
      _loadingBook = false;

      final initial = widget.initialBook!;
      _trackView(initial);
      _fetchSimilar(initial.title);
      _fetchUserInteraction(initial.isbn13);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final auth = context.read<AuthProvider>();
        if (auth.currentUser?.id != null) {
          _getNotesProvider(context)?.loadBookNotes(initial.isbn13, userId: auth.currentUser!.id);
        }
      });

      if (widget.isbn != '_' && widget.isbn.trim().isNotEmpty) {
        _fetchBook();
      }
      return;
    }
    _fetchBook();
  }

  Future<void> _fetchUserInteraction(String isbn, {String? targetUserId}) async {
    final auth = context.read<AuthProvider>();
    final uid = targetUserId ?? auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      if (mounted && _activeInteraction != null) {
        setState(() => _activeInteraction = null);
      }
      return;
    }

    // Check pending offline outbox first for immediate offline desired state
    final recProvider = context.read<RecommendationProvider>();
    final pendingItem = recProvider
        .getPendingInteractions(uid)
        .where((item) => item.isbn13 == isbn)
        .firstOrNull;
    if (pendingItem != null) {
      if (mounted && auth.currentUser?.id == uid) {
        setState(() {
          _activeInteraction =
              (pendingItem.interaction == 'clear' || pendingItem.interaction == 'remove')
                  ? null
                  : pendingItem.interaction;
        });
      }
      return;
    }

    try {
      final detailsUseCase = context.read<ViewBookDetailsUseCase>();
      final interaction = await detailsUseCase.getUserInteraction(uid, isbn);
      if (mounted && auth.currentUser?.id == uid) {
        setState(() => _activeInteraction = interaction);
      }
    } catch (_) {}
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

    if (_book == null) {
      setState(() {
        _loadingBook = true;
        _bookError = null;
      });
    }
    try {
      // 1. Try Supabase (Most reliable for 6k+ books)
      Book? book = await context.read<ViewBookDetailsUseCase>().getBookByIsbn(isbn);

      // 2. Fallback to Flask Api handled inside BookRepositoryImpl.getBookByIsbn
      if (!mounted) return;
      setState(() {
        _book = book ?? _book;
        _loadingBook = false;
        _bookError = (_book == null) ? context.tr('no_books_found') : null;
      });

      if (book != null) {
        _fetchUserInteraction(book.isbn13);
        final auth = context.read<AuthProvider>();
        if (auth.currentUser?.id != null) {
          _getNotesProvider(context)?.loadBookNotes(book.isbn13, userId: auth.currentUser!.id);
        }
        if (widget.initialBook == null) {
          _trackView(book);
          _fetchSimilar(book.title);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBook = false;
          if (_book == null) {
            _bookError = context.tr('error_loading_books');
          }
        });
      }
    }
  }

  Future<void> _fetchSimilar(String title) async {
    setState(() => _loadingSimilar = true);
    try {
      final recs = await context.read<ViewBookDetailsUseCase>().getSimilarBooks(title);
      if (mounted) setState(() => _similar = recs);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSimilar = false);
    }
  }

  Future<void> _handleInteraction(Book book, String interaction) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('please_log_in'))),
      );
      context.push('/login');
      return;
    }
    HapticFeedback.lightImpact();
    final isClearing = _activeInteraction == interaction;
    final nextInteraction = isClearing ? 'clear' : interaction;
    final prev = _activeInteraction;
    setState(() => _activeInteraction = isClearing ? null : interaction);

    try {
      final success = await context.read<RecommendationProvider>().submitFeedback(
        userId: auth.currentUser!.id,
        bookId: book.isbn13,
        interaction: nextInteraction,
      );
      if (!mounted) return;
      if (!success) {
        setState(() => _activeInteraction = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('update_failed')),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      final isQueued = context.read<RecommendationProvider>().hasPendingInteraction(auth.currentUser!.id, book.isbn13);
      if (isQueued) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('saved_offline_sync_later')),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (isClearing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('status_cleared')),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        final label = switch (interaction) {
          'want_to_read' => context.tr('want_to_read'),
          'reading' => context.tr('reading'),
          'finished' => context.tr('finished'),
          'like' => context.tr('like'),
          'dislike' => context.tr('dislike'),
          _ => interaction,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('marked_as', args: {'label': label})),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _activeInteraction = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('error_loading_books')),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _trackView(Book book) {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    final uid = auth.currentUser!.id;
    context.read<ManageRecommendationsUseCase>().trackActivity(
      userId: uid,
      activityType: 'view',
      bookId: book.isbn13,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final currentUid = auth.currentUser?.id;
    if (_loadedInteractionUserId != currentUid) {
      _loadedInteractionUserId = currentUid;
      _activeInteraction = null;
      if (currentUid != null && _book != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.read<AuthProvider>().currentUser?.id == currentUid) {
            _fetchUserInteraction(_book!.isbn13, targetUserId: currentUid);
            _getNotesProvider(context)?.loadBookNotes(_book!.isbn13, userId: currentUid);
          }
        });
      } else if (currentUid == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _getNotesProvider(context)?.clear();
          }
        });
      }
    }

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
      bottomNavigationBar: _buildBottomActionBar(context, book, isFavorite),
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
                  const SizedBox(height: DesignSystem.spacing32),
                  _buildLearningNotesSection(context, book),
                  const SizedBox(height: DesignSystem.spacing32),
                  if (_similar.isNotEmpty || _loadingSimilar) ...[
                    Text(
                      context.tr('similar_books'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: DesignSystem.spacing20),
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
    final theme = Theme.of(context);
    final auth = context.read<AuthProvider>();
    final favs = context.read<FavoritesProvider>();

    return SliverAppBar(
      expandedHeight: 400,
      pinned: true,
      stretch: true,
      backgroundColor: theme.colorScheme.surface,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Dynamic Cover Ambiance
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 1.2,
                  colors: [
                    _resolveCoverAmbiance(book, theme.brightness),
                    theme.colorScheme.surface,
                  ],
                ),
              ),
            ),
            Hero(
              tag: 'cover_${book.isbn13}',
              child: ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.25),
                      theme.colorScheme.surface,
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
          backgroundColor: Colors.black38,
          child: IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? DesignSystem.statusFavorite : Colors.white,
            ),
            tooltip: isFavorite ? context.tr('unfavorite') : context.tr('add_to_favorites'),
            onPressed: () {
              final uid = auth.currentUser?.id;
              if (uid == null) {
                context.push('/login');
                return;
              }
              HapticFeedback.mediumImpact();
              final willBeFav = !isFavorite;
              favs.toggleFavorite(userId: uid, book: book);
              if (favs.hasPendingSync(book.isbn13)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('saved_offline_sync_later')),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
              if (willBeFav) {
                context.read<RecommendationProvider>().submitFeedback(
                  userId: uid,
                  bookId: book.isbn13,
                  interaction: 'favorite',
                );
              } else {
                context.read<RecommendationProvider>().submitFeedback(
                  userId: uid,
                  bookId: book.isbn13,
                  interaction: 'unfavorite',
                );
              }
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
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: DesignSystem.spacing8),
        Text(
          book.authorsFormatted,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_activeInteraction != null &&
            ['reading', 'finished', 'want_to_read'].contains(_activeInteraction)) ...[
          const SizedBox(height: DesignSystem.spacing12),
          _buildActiveStatusBadge(context, _activeInteraction!),
        ],
      ],
    );
  }

  Widget _buildActiveStatusBadge(BuildContext context, String status) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case 'reading':
        bg = DesignSystem.statusReading.withOpacity(0.18);
        fg = DesignSystem.statusReading;
        icon = Icons.auto_stories_rounded;
        label = context.tr('currently_reading');
        break;
      case 'finished':
        bg = DesignSystem.statusFinished.withOpacity(0.18);
        fg = DesignSystem.statusFinished;
        icon = Icons.check_circle_rounded;
        label = context.tr('finished_reading');
        break;
      case 'want_to_read':
      default:
        bg = DesignSystem.statusWantToRead.withOpacity(0.18);
        fg = DesignSystem.statusWantToRead;
        icon = Icons.bookmark_add_rounded;
        label = context.tr('in_reading_list');
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: DesignSystem.borderRadiusPill,
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context, Book book) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RatingBarIndicator(
                  rating: book.averageRating.clamp(0.0, 5.0),
                  itemBuilder: (_, __) =>
                      const Icon(Icons.star, color: DesignSystem.rating),
                  itemCount: 5,
                  itemSize: 18,
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
        if (book.pageCount > 0)
          _StatItem(label: context.tr('page_count'), value: book.pageCount.toString()),
        if (book.publishedDate.isNotEmpty)
          _StatItem(label: context.tr('year'), value: book.publishedDate.split('-').first),
        if (book.isbn13.isNotEmpty && book.isbn13 != '_')
          _StatItem(label: 'ISBN', value: book.isbn13),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, Book book) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () =>
                    context.push('/recommend/${Uri.encodeComponent(book.title)}'),
                icon: const Icon(Icons.auto_awesome),
                label: Text(context.tr('ai_insight')),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: DesignSystem.spacing16),
                  shape: RoundedRectangleBorder(
                      borderRadius: DesignSystem.borderRadiusLarge),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('reading_status'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ReadingStatusChip(
                book: book,
                interaction: 'want_to_read',
                icon: Icons.bookmark_add_outlined,
                label: context.tr('want_to_read'),
                color: DesignSystem.statusWantToRead,
                isSelected: _activeInteraction == 'want_to_read',
                onSelected: (interaction) => _handleInteraction(book, interaction),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ReadingStatusChip(
                book: book,
                interaction: 'reading',
                icon: Icons.auto_stories_outlined,
                label: context.tr('reading'),
                color: DesignSystem.statusReading,
                isSelected: _activeInteraction == 'reading',
                onSelected: (interaction) => _handleInteraction(book, interaction),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ReadingStatusChip(
                book: book,
                interaction: 'finished',
                icon: Icons.check_circle_outline,
                label: context.tr('finished'),
                color: DesignSystem.statusFinished,
                isSelected: _activeInteraction == 'finished',
                onSelected: (interaction) => _handleInteraction(book, interaction),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            _SignalChip(
              book: book,
              interaction: 'like',
              icon: Icons.thumb_up_rounded,
              outlineIcon: Icons.thumb_up_outlined,
              label: context.tr('like'),
              color: DesignSystem.statusLike,
              isSelected: _activeInteraction == 'like',
              onSelected: (interaction) => _handleInteraction(book, interaction),
            ),
            _SignalChip(
              book: book,
              interaction: 'dislike',
              icon: Icons.thumb_down_rounded,
              outlineIcon: Icons.thumb_down_outlined,
              label: context.tr('dislike'),
              color: DesignSystem.statusDislike,
              isSelected: _activeInteraction == 'dislike',
              onSelected: (interaction) => _handleInteraction(book, interaction),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDescription(BuildContext context, Book book) {
    if (book.description.isEmpty && book.explanation == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (book.explanation != null) ...[
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacing16),
            margin: const EdgeInsets.only(bottom: DesignSystem.spacing24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.08),
              borderRadius: DesignSystem.borderRadiusLarge,
              border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: DesignSystem.spacing12),
                Expanded(
                  child: Text(
                    book.explanation!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (book.description.isNotEmpty) ...[
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
      ],
    );
  }

  Widget _buildSimilarList() {
    if (_loadingSimilar) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _similar.length; i++) ...[
              BookCard(book: _similar[i]),
              if (i < _similar.length - 1)
                const SizedBox(width: 16),
            ]
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  String _formatInteractionLabel(String interaction) {
    switch (interaction) {
      case 'want_to_read':
        return context.tr('want_to_read');
      case 'reading':
        return context.tr('reading');
      case 'finished':
        return context.tr('finished');
      default:
        return context.tr('view_my_library');
    }
  }

  Widget _buildBottomActionBar(BuildContext context, Book book, bool isFavorite) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.read<AuthProvider>();
    final favs = context.read<FavoritesProvider>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? DesignSystem.surfaceDark : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        boxShadow: DesignSystem.shadowLg(isDark),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: isFavorite
                    ? DesignSystem.statusFavorite.withOpacity(0.15)
                    : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                borderRadius: DesignSystem.borderRadiusLarge,
              ),
              child: IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite
                      ? DesignSystem.statusFavorite
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
                tooltip: isFavorite ? context.tr('unfavorite') : context.tr('add_to_favorites'),
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
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showLibraryBottomSheet(context, book),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: DesignSystem.borderRadiusLarge),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bookmark_outline_rounded, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _activeInteraction != null
                            ? _formatInteractionLabel(_activeInteraction!)
                            : context.tr('add_to_library'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLibraryBottomSheet(BuildContext context, Book book) {
    final auth = context.read<AuthProvider>();
    final favs = context.read<FavoritesProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? DesignSystem.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isFav = favs.isFavorite(book.isbn13);
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (book.authors.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        book.authors,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: isDark ? Colors.white60 : Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    _buildSheetActionTile(
                      icon: isFav ? Icons.favorite : Icons.favorite_border,
                      title: isFav ? context.tr('unfavorite') : context.tr('add_to_favorites'),
                      color: DesignSystem.statusFavorite,
                      isSelected: isFav,
                      onTap: () {
                        final uid = auth.currentUser?.id;
                        if (uid == null) {
                          Navigator.pop(bottomSheetContext);
                          context.push('/login');
                          return;
                        }
                        HapticFeedback.mediumImpact();
                        favs.toggleFavorite(userId: uid, book: book);
                        setSheetState(() {});
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSheetActionTile(
                      icon: Icons.auto_stories_rounded,
                      title: context.tr('reading'),
                      color: DesignSystem.statusReading,
                      isSelected: _activeInteraction == 'reading',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _handleInteraction(book, 'reading');
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSheetActionTile(
                      icon: Icons.bookmark_add_rounded,
                      title: context.tr('want_to_read'),
                      color: DesignSystem.statusWantToRead,
                      isSelected: _activeInteraction == 'want_to_read',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _handleInteraction(book, 'want_to_read');
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSheetActionTile(
                      icon: Icons.check_circle_rounded,
                      title: context.tr('finished'),
                      color: DesignSystem.statusFinished,
                      isSelected: _activeInteraction == 'finished',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _handleInteraction(book, 'finished');
                        setSheetState(() {});
                      },
                    ),
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

  Widget _buildSheetActionTile({
    required IconData icon,
    required String title,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
      borderRadius: DesignSystem.borderRadiusLarge,
      child: InkWell(
        borderRadius: DesignSystem.borderRadiusLarge,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? color : (isDark ? Colors.white70 : Colors.black54), size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? color : null,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }

Widget _buildLearningNotesSection(BuildContext context, Book book) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final notesProvider = _getNotesProvider(context, listen: true);

    if (notesProvider == null) {
      return const SizedBox.shrink();
    }

    final isDark = theme.brightness == Brightness.dark;
    final notes = notesProvider.getBookNotes(book.isbn13);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('learning_notes'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${notes.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (auth.isLoggedIn)
              TextButton.icon(
                key: const Key('add_note_button'),
                onPressed: () => _showNoteModal(context, book),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(context.tr('add_note')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!auth.isLoggedIn)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 32,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('sign_in_to_add_notes'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/login'),
                  child: Text(context.tr('sign_in_hint')),
                ),
              ],
            ),
          )
        else if (notesProvider.isLoading && notes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (notesProvider.errorMessage != null && notes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  notesProvider.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => notesProvider.loadBookNotes(book.isbn13, userId: auth.currentUser?.id),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(context.tr('retry')),
                ),
              ],
            ),
          )
        else if (notes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 36,
                  color: theme.colorScheme.primary.withOpacity(0.6),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('empty_notes_book'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  key: const Key('add_first_note_button'),
                  onPressed: () => _showNoteModal(context, book),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(context.tr('add_note')),
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: notes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final note = notes[index];
              return _buildNoteCard(context, book, note);
            },
          ),
      ],
    );
  }

  Widget _buildNoteCard(BuildContext context, Book book, LearningNote note) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
      key: Key('note_card_${note.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
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
                key: Key('edit_note_button_${note.id}'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: context.tr('edit_note'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showNoteModal(context, book, existingNote: note),
              ),
              const SizedBox(width: 10),
              IconButton(
                key: Key('delete_note_button_${note.id}'),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                tooltip: context.tr('delete_note'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: theme.colorScheme.error.withOpacity(0.8),
                onPressed: () => _confirmDeleteNote(context, book, note),
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
        ],
      ),
    );
  }

  void _showNoteModal(BuildContext context, Book book, {LearningNote? existingNote}) {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.currentUser == null) {
      context.push('/login');
      return;
    }

    final isEditing = existingNote != null;
    String selectedType = existingNote?.noteType ?? 'personal_note';
    final textController = TextEditingController(text: existingNote?.content ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final theme = Theme.of(modalContext);
            final isDark = theme.brightness == Brightness.dark;

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E222A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isEditing ? context.tr('edit_note') : context.tr('add_note'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildNoteTypeChip(
                          modalContext,
                          type: 'personal_note',
                          label: context.tr('note_type_personal_note'),
                          icon: Icons.sticky_note_2_outlined,
                          isSelected: selectedType == 'personal_note',
                          onTap: () => setModalState(() => selectedType = 'personal_note'),
                        ),
                        _buildNoteTypeChip(
                          modalContext,
                          type: 'key_takeaway',
                          label: context.tr('note_type_key_takeaway'),
                          icon: Icons.lightbulb_rounded,
                          isSelected: selectedType == 'key_takeaway',
                          onTap: () => setModalState(() => selectedType = 'key_takeaway'),
                        ),
                        _buildNoteTypeChip(
                          modalContext,
                          type: 'question',
                          label: context.tr('note_type_question'),
                          icon: Icons.help_outline_rounded,
                          isSelected: selectedType == 'question',
                          onTap: () => setModalState(() => selectedType = 'question'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('note_content_textfield'),
                      controller: textController,
                      maxLines: 6,
                      minLines: 3,
                      maxLength: 5000,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: context.tr('note_content_placeholder'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(modalContext).pop(),
                          child: Text(context.tr('cancel')),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          key: const Key('save_note_button'),
                          onPressed: () async {
                            final content = textController.text.trim();
                            if (content.isEmpty) return;

                            final notesProvider = _getNotesProvider(context);
                            if (notesProvider == null) return;

                            final messenger = ScaffoldMessenger.of(context);
                            final trSaved = context.tr('note_saved');
                            final trFailed = context.tr('update_failed');

                            Navigator.of(modalContext).pop();

                            bool success;
                            if (isEditing) {
                              success = await notesProvider.editNote(
                                noteId: existingNote.id,
                                bookId: book.isbn13,
                                content: content,
                                noteType: selectedType,
                              );
                            } else {
                              success = await notesProvider.addNote(
                                bookId: book.isbn13,
                                noteType: selectedType,
                                content: content,
                                userId: auth.currentUser!.id,
                              );
                            }

                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  success ? trSaved : trFailed,
                                ),
                                backgroundColor: success ? null : Colors.redAccent,
                              ),
                            );
                          },
                          child: Text(context.tr('save')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNoteTypeChip(
    BuildContext context, {
    required String type,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    Color chipColor;
    switch (type) {
      case 'key_takeaway':
        chipColor = const Color(0xFFF59E0B);
        break;
      case 'question':
        chipColor = const Color(0xFF8B5CF6);
        break;
      case 'personal_note':
      default:
        chipColor = const Color(0xFF3B82F6);
        break;
    }

    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) => onTap(),
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : chipColor),
      label: Text(label),
      selectedColor: chipColor,
      backgroundColor: chipColor.withOpacity(0.12),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
    );
  }

  void _confirmDeleteNote(BuildContext context, Book book, LearningNote note) {
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
              key: const Key('confirm_delete_note_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final trDeleted = context.tr('note_deleted');
                final trFailed = context.tr('update_failed');
                Navigator.of(dialogContext).pop();
                final notesProvider = _getNotesProvider(context);
                if (notesProvider == null) return;
                final ok = await notesProvider.removeNote(noteId: note.id, bookId: book.isbn13);
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


class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
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

class _ReadingStatusChip extends StatelessWidget {
  final Book book;
  final String interaction;
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final ValueChanged<String> onSelected;

  const _ReadingStatusChip({
    required this.book,
    required this.interaction,
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onSelected(interaction),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? color
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected
                    ? color
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  final Book book;
  final String interaction;
  final IconData icon;
  final IconData outlineIcon;
  final String label;
  final Color color;
  final bool isSelected;
  final ValueChanged<String> onSelected;

  const _SignalChip({
    required this.book,
    required this.interaction,
    required this.icon,
    required this.outlineIcon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onSelected(interaction),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? icon : outlineIcon,
              size: 16,
              color: isSelected
                  ? color
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? color
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
