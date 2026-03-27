import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:go_router/go_router.dart';
import '../models/book_model.dart';

// ── Vertical book card (used in grids & lists) ────────────────────────────────

class BookCard extends StatelessWidget {
  const BookCard({super.key, required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push('/book/${book.isbn13}'),
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: book.coverUrl,
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 190,
                  color: colors.surface,
                  child: const Center(child: _CoverPlaceholder()),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 190,
                  color: colors.surface,
                  child: const Center(child: _CoverPlaceholder()),
                ),
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.authorsFormatted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  _RatingRow(rating: book.averageRating),
                ],
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/book/${book.isbn13}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
              child: CachedNetworkImage(
                imageUrl: book.coverUrl,
                width: 76,
                height: 110,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 76,
                  height: 110,
                  color: Theme.of(context).colorScheme.surface,
                  child: const Center(child: _CoverPlaceholder(size: 24)),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 76,
                  height: 110,
                  color: Theme.of(context).colorScheme.surface,
                  child: const Center(child: _CoverPlaceholder(size: 24)),
                ),
              ),
            ),

            // Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.authorsFormatted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    _RatingRow(rating: book.averageRating),
                    if (book.primaryCategory.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _CategoryChip(label: book.primaryCategory),
                    ],
                  ],
                ),
              ),
            ),

            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: trailing!,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Featured hero card ────────────────────────────────────────────────────────

class FeaturedBookCard extends StatelessWidget {
  const FeaturedBookCard({super.key, required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/book/${book.isbn13}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.8),
              Theme.of(context).colorScheme.secondary.withOpacity(0.5),
            ],
          ),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: book.coverUrl,
                  width: 110,
                  height: 160,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox(
                      width: 110, height: 160, child: Center(child: _CoverPlaceholder())),
                  errorWidget: (_, __, ___) => const SizedBox(
                      width: 110, height: 160, child: Center(child: _CoverPlaceholder())),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        book.primaryCategory.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.authorsFormatted,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    _RatingRow(rating: book.averageRating, color: Colors.white),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.menu_book_rounded,
        size: size, color: Theme.of(context).colorScheme.primary.withOpacity(0.4));
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating, this.color});
  final double rating;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RatingBarIndicator(
          rating: rating.clamp(0.0, 5.0),
          itemBuilder: (_, __) => Icon(Icons.star, color: color ?? const Color(0xFFFFD166)),
          itemCount: 5,
          itemSize: 12,
        ),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
