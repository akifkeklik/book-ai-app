import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class BookCardSkeleton extends StatelessWidget {
  const BookCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.white.withOpacity(0.05),
      highlightColor: Colors.white.withOpacity(0.1),
      child: Container(
        width: 145,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AspectRatio(
              aspectRatio: 2 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: 100, color: Colors.white10),
                  const SizedBox(height: 6),
                  Container(height: 10, width: 60, color: Colors.white10),
                  const SizedBox(height: 12),
                  Container(height: 12, width: 80, color: Colors.white10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  final double height;
  const SkeletonList({super.key, this.height = 300});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 5; i++) ...[
              const BookCardSkeleton(),
              if (i < 4) const SizedBox(width: 12),
            ]
          ],
        ),
      ),
    );
  }
}
