import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:go_router/go_router.dart';

import '../models/book_model.dart';
import '../providers/language_provider.dart';
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
              color: Theme.of(context).colorScheme.surfaceVariant,
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
        color: Theme.of(context).colorScheme.surfaceVariant,
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
                  if (book.similarityScore != null && book.similarityScore! > 0)
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 10, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              context.tr(
                                  'explore'), // or a new key like 'suggested'
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
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
                        if (book.aiNote != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(Icons.auto_awesome,
                                    size: 10, color: colors.primary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    book.aiNote!,
                                    maxLines: 1,
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
                    if (book.aiNote != null) ...[
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
                                book.aiNote!,
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
