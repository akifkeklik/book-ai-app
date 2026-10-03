import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/catalog_provider.dart';
import '../providers/language_provider.dart';
import '../theme/design_system.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            toolbarHeight: 64,
            title: Text(
              context.tr('categories'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final cat = catalog.defaultGenres[index];
                  return _CategoryCard(category: cat);
                },
                childCount: catalog.defaultGenres.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String category;

  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final icon = _getIconForCategory(category);
    final gradient = _getGradientForCategory(category, isDark);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: DesignSystem.borderRadiusLarge,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(isDark ? 0.15 : 0.3),
        ),
      ),
      child: InkWell(
        onTap: () => context.push('/category/${Uri.encodeComponent(category)}'),
        child: Container(
          decoration: BoxDecoration(gradient: gradient),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: DesignSystem.borderRadiusMedium,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const Spacer(),
              Text(
                context.trGenre(category),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                context.tr('explore_category'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withOpacity(0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForCategory(String cat) {
    switch (cat) {
      case 'Fiction':
        return Icons.auto_stories_rounded;
      case 'Young Adult & Children':
        return Icons.child_care_rounded;
      case 'History':
        return Icons.history_edu_rounded;
      case 'Drama & Plays':
        return Icons.theater_comedy_rounded;
      case 'Philosophy':
        return Icons.psychology_alt_rounded;
      case 'Religion & Spirituality':
        return Icons.church_rounded;
      case 'Poetry':
        return Icons.edit_note_rounded;
      case 'Science':
        return Icons.science_rounded;
      case 'Social Sciences':
        return Icons.groups_rounded;
      case 'Art & Design':
        return Icons.palette_rounded;
      case 'Food & Cooking':
        return Icons.restaurant_rounded;
      case 'Psychology':
        return Icons.face_rounded;
      case 'Self-Development':
        return Icons.trending_up_rounded;
      case 'Technology':
        return Icons.computer_rounded;
      case 'Travel':
        return Icons.flight_rounded;
      case 'Mystery & Thriller':
        return Icons.search_rounded;
      case 'Humor & Satire':
        return Icons.sentiment_very_satisfied_rounded;
      case 'Fantasy':
        return Icons.auto_awesome_rounded;
      case 'Health & Wellness':
        return Icons.monitor_heart_rounded;
      case 'Biography & Memoir':
        return Icons.person_rounded;
      case 'Science Fiction':
        return Icons.rocket_launch_rounded;
      case 'Horror':
        return Icons.nightlight_round;
      case 'Comics & Graphic Novels':
        return Icons.image_rounded;
      case 'Romance':
        return Icons.favorite_border_rounded;
      case 'Business':
        return Icons.business_center_rounded;
      default:
        return Icons.book_rounded;
    }
  }

  LinearGradient _getGradientForCategory(String cat, bool isDark) {
    const gradients = <String, List<Color>>{
      'Fiction': [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      'Young Adult & Children': [Color(0xFFF59E0B), Color(0xFFEF4444)],
      'History': [Color(0xFF92400E), Color(0xFF78350F)],
      'Drama & Plays': [Color(0xFF7C3AED), Color(0xFF4C1D95)],
      'Philosophy': [Color(0xFF1D4ED8), Color(0xFF1E40AF)],
      'Religion & Spirituality': [Color(0xFF065F46), Color(0xFF047857)],
      'Poetry': [Color(0xFFDB2777), Color(0xFF9D174D)],
      'Science': [Color(0xFF0284C7), Color(0xFF0369A1)],
      'Social Sciences': [Color(0xFF0891B2), Color(0xFF164E63)],
      'Art & Design': [Color(0xFFEA580C), Color(0xFF9A3412)],
      'Food & Cooking': [Color(0xFFD97706), Color(0xFF92400E)],
      'Psychology': [Color(0xFF7C3AED), Color(0xFF6D28D9)],
      'Self-Development': [Color(0xFF059669), Color(0xFF065F46)],
      'Technology': [Color(0xFF475569), Color(0xFF1E293B)],
      'Travel': [Color(0xFF0EA5E9), Color(0xFF0284C7)],
      'Mystery & Thriller': [Color(0xFF374151), Color(0xFF111827)],
      'Humor & Satire': [Color(0xFFF59E0B), Color(0xFFD97706)],
      'Fantasy': [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
      'Health & Wellness': [Color(0xFF10B981), Color(0xFF059669)],
      'Biography & Memoir': [Color(0xFF6B7280), Color(0xFF4B5563)],
      'Science Fiction': [Color(0xFF2563EB), Color(0xFF1D4ED8)],
      'Horror': [Color(0xFF1F2937), Color(0xFF111827)],
      'Comics & Graphic Novels': [Color(0xFFDC2626), Color(0xFFB91C1C)],
      'Romance': [Color(0xFFEC4899), Color(0xFFDB2777)],
      'Business': [Color(0xFF1E3A5F), Color(0xFF1E40AF)],
    };

    final colors = gradients[cat] ?? [const Color(0xFF6366F1), const Color(0xFF4F46E5)];
    return LinearGradient(
      colors: isDark
          ? [colors[0].withOpacity(0.82), colors[1].withOpacity(0.82)]
          : colors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
