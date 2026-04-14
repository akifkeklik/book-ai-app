import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/book_provider.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final books = context.watch<BookProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('categories')),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: books.defaultGenres.length,
        itemBuilder: (context, index) {
          final cat = books.defaultGenres[index];
          return _buildCategoryCard(context, cat);
        },
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, String cat) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/category/$cat'),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer.withOpacity(0.3),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // Decorative Icon in background
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(
                  Icons.auto_stories,
                  size: 100,
                  color: theme.colorScheme.primary.withOpacity(0.05),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIconForCategory(cat),
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.trGenre(cat),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr('explore_category'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: theme.colorScheme.primary.withOpacity(0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForCategory(String cat) {
    switch (cat.toLowerCase()) {
      case 'fiction': return Icons.auto_stories;
      case 'science': return Icons.science;
      case 'history': return Icons.history_edu;
      case 'mystery': return Icons.search;
      case 'fantasy': return Icons.auto_awesome;
      case 'biography': return Icons.person;
      case 'self-help': return Icons.psychology;
      case 'business': return Icons.business_center;
      case 'romance': return Icons.favorite;
      case 'thriller': return Icons.dangerous;
      case 'philosophy': return Icons.menu_book;
      case 'art': return Icons.palette;
      case 'cooking': return Icons.restaurant;
      case 'religion': return Icons.church;
      case 'computers': return Icons.computer;
      case 'psychology': return Icons.face;
      case 'social science': return Icons.public;
      case 'poetry': return Icons.edit_note;
      case 'travel': return Icons.flight;
      default: return Icons.book;
    }
  }
}
