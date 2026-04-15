import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book_model.dart';
import '../providers/auth_provider.dart';
import '../providers/book_provider.dart';
import 'book_cover_fallback.dart';

// ── Shared Multi-layer Fallback Cover ───────────────────────────────────────
class NetworkCoverWithFallback extends StatelessWidget {
  final Book book;
  final double width;
  final double height;

  const NetworkCoverWithFallback({
    super.key,
    required this.book,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Stage 3: The typographic fallback
    final Widget fallbackWidget = BookCoverFallback(
      title: book.title,
      author: book.authorsFormatted,
      width: width,
      height: height,
    );

    // Stage 2: OpenLibrary Cover
    final Widget openLibraryWidget = book.openLibraryCoverUrl.isEmpty
        ? fallbackWidget
        : CachedNetworkImage(
            imageUrl: book.openLibraryCoverUrl,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => fallbackWidget,
            placeholder: (_, __) => Container(
              width: width,
              height: height,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          );

    // Stage 1: Primary Kaggle/DB Cover URL
    if (book.coverUrl.isEmpty) return openLibraryWidget;

    return CachedNetworkImage(
      imageUrl: book.coverUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => openLibraryWidget,
      placeholder: (_, __) => Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

// ── Vertical book card (used in grids & lists) ────────────────────────────────

class BookCard extends StatelessWidget {
  const BookCard({super.key, required this.book});
  final Book book;

  String get _detailRouteIsbn =>
      book.isbn13.trim().isEmpty ? '_' : book.isbn13.trim();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/book/$_detailRouteIsbn', extra: book);
      },
      child: Container(
        width: 145,
        margin: const EdgeInsets.only(bottom: 15, left: 4, right: 4, top: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'cover_${book.isbn13}',
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    child: NetworkCoverWithFallback(
                        book: book, width: double.infinity, height: 195),
                  ),
                  if (book.explanation != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.primary.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 10, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              "SİZİN İÇİN",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Debug Visibility Tooltip (Top Left)
                  if (book.finalScore != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bug_report,
                            size: 10, color: Colors.white70),
                      ),
                    ),
                ],
              ),
            ),

            // Info (Expanded guards against overflow)
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top content: Title and Author
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w700, height: 1.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          book.authorsFormatted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.onSurface.withOpacity(0.6),
                                  ),
                        ),
                      ],
                    ),

                    // Bottom content: AI Note and Rating (Anchored)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (book.explanation != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(Icons.auto_awesome,
                                    size: 10, color: colors.primary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    book.explanation!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w600,
                                      color: colors.primary.withOpacity(0.9),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _RatingRow(rating: book.averageRating),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: _InteractionButtons(book: book),
                          ),
                        ),
                      ],
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
}

// ── Horizontal book card (used in featured / search results) ──────────────────

class BookListTile extends StatelessWidget {
  const BookListTile({super.key, required this.book, this.trailing});
  final Book book;
  final Widget? trailing;

  String get _detailRouteIsbn =>
      book.isbn13.trim().isEmpty ? '_' : book.isbn13.trim();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push('/book/$_detailRouteIsbn', extra: book),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            Hero(
              tag: 'cover_${book.isbn13}',
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(16)),
                child: NetworkCoverWithFallback(
                    book: book, width: 85, height: 120),
              ),
            ),

            // Details
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.authorsFormatted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withOpacity(0.6),
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (book.explanation != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 12, color: colors.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                book.explanation!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colors.primary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        _RatingRow(rating: book.averageRating),
                        const SizedBox(width: 12),
                        if (book.primaryCategory.isNotEmpty)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _CategoryChip(label: book.primaryCategory),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: trailing!,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Featured hero card (Glassmorphism & Rich Aesthetics) ────────────────────

class FeaturedBookCard extends StatelessWidget {
  const FeaturedBookCard({super.key, required this.book});
  final Book book;

  String get _detailRouteIsbn =>
      book.isbn13.trim().isEmpty ? '_' : book.isbn13.trim();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/book/$_detailRouteIsbn', extra: book),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        // Removed fixed height: 220 to avoid overflows on small devices or with long titles
        constraints: const BoxConstraints(minHeight: 200, maxHeight: 260),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).cardTheme.color,
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative background circles
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),

            // Content
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Hero(
                    tag: 'cover_${book.isbn13}',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(5, 5),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: NetworkCoverWithFallback(
                            book: book, width: 125, height: 180),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(top: 24, bottom: 24, right: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Glassmorphism category pill
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.2)),
                              ),
                              child: Text(
                                book.primaryCategory.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          book.authorsFormatted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.7)),
                        ),
                        const Spacer(),
                        _RatingRow(
                            rating: book.averageRating,
                            color: const Color(0xFFFFD166)),
                      ],
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

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating, this.color});
  final double rating;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RatingBarIndicator(
          rating: rating.clamp(0.0, 5.0),
          itemBuilder: (_, __) =>
              Icon(Icons.star_rounded, color: color ?? const Color(0xFFFFD166)),
          itemCount: 5,
          itemSize: 14,
          unratedColor: (color ?? const Color(0xFFFFD166)).withOpacity(0.2),
        ),
        const SizedBox(width: 6),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color ?? const Color(0xFFFFD166)),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InteractionButtons extends StatelessWidget {
  final Book book;
  const _InteractionButtons({required this.book});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bp = context.read<BookProvider>();
    final auth = context.read<AuthProvider>();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () {
            HapticFeedback.mediumImpact();
            if (auth.currentUser != null) {
              bp.submitFeedback(
                userId: auth.currentUser!.id,
                bookId: book.isbn13,
                interaction: 'like',
              );
            }
          },
          icon: const Icon(Icons.thumb_up_alt_outlined, size: 14),
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          visualDensity: VisualDensity.compact,
          splashRadius: 14,
          color: colors.primary,
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () {
            HapticFeedback.heavyImpact();
            if (auth.currentUser != null) {
              bp.submitFeedback(
                userId: auth.currentUser!.id,
                bookId: book.isbn13,
                interaction: 'dislike',
              );
            }
          },
          icon: const Icon(Icons.thumb_down_alt_outlined, size: 14),
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          visualDensity: VisualDensity.compact,
          splashRadius: 14,
          color: colors.error,
        ),
        if (book.finalScore != null) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Theme.of(context).cardColor,
                  title: const Text("AI Analizi (Debug)",
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Kaynak: ${book.explanationSourceBook}",
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      const Divider(color: Colors.white10),
                      _debugScoreRow(
                          "İçerik Benzerliği", book.rawSimilarityScore),
                      _debugScoreRow(
                          "Çeşitlilik Cezası", book.diversityPenalty),
                      const SizedBox(height: 8),
                      Text("Final Skor: ${book.finalScore}",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                              fontSize: 14)),
                    ],
                  ),
                ),
              );
            },
            child: Icon(Icons.info_outline,
                size: 12, color: colors.onSurface.withOpacity(0.3)),
          ),
        ],
      ],
    );
  }

  Widget _debugScoreRow(String label, double? score) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text(score?.toStringAsFixed(4) ?? "0.0000",
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}
