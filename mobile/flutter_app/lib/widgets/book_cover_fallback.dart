import 'package:flutter/material.dart';
import '../theme/pastel_colors.dart';

class BookCoverFallback extends StatelessWidget {
  const BookCoverFallback({
    super.key,
    required this.title,
    required this.author,
    this.width,
    this.height,
  });

  final String title;
  final String author;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // Dynamically pick a pastel seed color based on the book title
    final Color bgColor = AppPastels.getColorForString(title);
    
    // Determine luminance to provide high-contrast text color
    final bool isDark = bgColor.computeLuminance() < 0.5;
    final Color textColor = isDark ? Colors.white : const Color(0xFF1E1E2C);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bgColor,
            bgColor.withOpacity(0.7),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Background typography aesthetic (Watermark)
          Positioned(
            right: -20,
            bottom: -20,
            child: Opacity(
              opacity: 0.15,
              child: Text(
                title.isNotEmpty ? title[0].toUpperCase() : 'B',
                style: TextStyle(
                  fontSize: (width ?? 120) * 1.5,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: textColor,
                ),
              ),
            ),
          ),
          
          // Foreground Content
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                  ),
                ),
                Text(
                  author,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: textColor.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
