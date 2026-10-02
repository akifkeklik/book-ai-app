import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:go_router/go_router.dart';

import '../domain/entities/book.dart';
import '../providers/language_provider.dart';
import '../theme/design_system.dart';
import 'book_cover_fallback.dart';

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
    final Widget fallbackWidget = BookCoverFallback(
      title: book.title,
      author: book.authorsFormatted,
      width: width,
      height: height,
    );

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

class BookCard extends StatelessWidget {
  const BookCard({super.key, required this.book});
  final Book book;

  String get _detailRouteIsbn => book.isbn13.trim().isEmpty ? '_' : book.isbn13.trim();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/book/$_detailRouteIsbn', extra: book);
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(bottom: DesignSystem.spacing16, top: DesignSystem.spacing4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: DesignSystem.borderRadiusLarge,
          border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
          boxShadow: DesignSystem.shadowMd(isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'cover_${book.isbn13}',
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(DesignSystem.radiusLarge)),
                    child: NetworkCoverWithFallback(book: book, width: double.infinity, height: 210),
                  ),
                  if (book.explanation != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: ClipRRect(
                        borderRadius: DesignSystem.borderRadiusPill,
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colors.primary.withOpacity(0.8),
                              borderRadius: DesignSystem.borderRadiusPill,
                              boxShadow: DesignSystem.shadowSm(true),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  context.tr('for_you').toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(DesignSystem.spacing12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          book.authorsFormatted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withOpacity(0.6),
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

class BookListTile extends StatelessWidget {
  const BookListTile({super.key, required this.book, this.trailing});
  final Book book;
  final Widget? trailing;

  String get _detailRouteIsbn => book.isbn13.trim().isEmpty ? '_' : book.isbn13.trim();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => context.push('/book/$_detailRouteIsbn', extra: book),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: DesignSystem.borderRadiusLarge,
          border: Border.all(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
          boxShadow: DesignSystem.shadowSm(isDark),
        ),
        child: Row(
          children: [
            Hero(
              tag: 'cover_${book.isbn13}',
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(DesignSystem.radiusLarge)),
                child: NetworkCoverWithFallback(book: book, width: 90, height: 130),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing16, vertical: DesignSystem.spacing12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.primary.withOpacity(0.08),
                          borderRadius: DesignSystem.borderRadiusSmall,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 12, color: colors.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                book.explanation!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary,
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

class FeaturedBookCard extends StatelessWidget {
  const FeaturedBookCard({super.key, required this.book});
  final Book book;

  String get _detailRouteIsbn => book.isbn13.trim().isEmpty ? '_' : book.isbn13.trim();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/book/$_detailRouteIsbn', extra: book),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        constraints: const BoxConstraints(minHeight: 200, maxHeight: 260),
        decoration: BoxDecoration(
          borderRadius: DesignSystem.borderRadiusLarge,
          color: Theme.of(context).cardTheme.color,
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: DesignSystem.shadowLg(true),
        ),
        child: Stack(
          children: [
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
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Hero(
                    tag: 'cover_${book.isbn13}',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: DesignSystem.borderRadiusMedium,
                        boxShadow: DesignSystem.shadowMd(true),
                      ),
                      child: ClipRRect(
                        borderRadius: DesignSystem.borderRadiusMedium,
                        child: NetworkCoverWithFallback(book: book, width: 125, height: 180),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 24, right: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: DesignSystem.borderRadiusSmall,
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: DesignSystem.borderRadiusSmall,
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: Text(
                                book.primaryCategory.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
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
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1.2, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          book.authorsFormatted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7)),
                        ),
                        const Spacer(),
                        _RatingRow(rating: book.averageRating, color: DesignSystem.rating),
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
          itemBuilder: (_, __) => Icon(Icons.star_rounded, color: color ?? DesignSystem.rating),
          itemCount: 5,
          itemSize: 14,
          unratedColor: (color ?? DesignSystem.rating).withOpacity(0.2),
        ),
        const SizedBox(width: 6),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color ?? DesignSystem.rating),
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
        borderRadius: DesignSystem.borderRadiusSmall,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800),
      ),
    );
  }
}
