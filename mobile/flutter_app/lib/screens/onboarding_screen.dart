import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../domain/entities/book.dart';
import '../providers/recommendation_provider.dart';
import '../providers/search_provider.dart';
import '../providers/language_provider.dart';
import '../application/use_cases/manage_user_profile_use_case.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;

  final List<String> _selectedCategories = [];
  final List<String> _selectedBooks = []; // ISBNs

  final List<Map<String, String>> _categories = [
    {'id': 'Fiction', 'icon': '📚'},
    {'id': 'Science', 'icon': '🔬'},
    {'id': 'History', 'icon': '🏛️'},
    {'id': 'Mystery', 'icon': '🔎'},
    {'id': 'Fantasy', 'icon': '🪄'},
    {'id': 'Biography', 'icon': '👤'},
    {'id': 'Self-Help', 'icon': '🌱'},
    {'id': 'Business', 'icon': '💼'},
    {'id': 'Romance', 'icon': '💖'},
    {'id': 'Thriller', 'icon': '⚡'},
    {'id': 'Philosophy', 'icon': '🧠'},
    {'id': 'Art', 'icon': '🎨'},
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId != null) {
      try {
        final profile = await context.read<ManageUserProfileUseCase>().getUserProfile(userId);
        if (profile != null && mounted) {
          final genres = profile['preferred_genres'] as List<dynamic>?;
          if (genres != null && genres.isNotEmpty) {
            setState(() {
              _selectedCategories.clear();
              _selectedCategories.addAll(genres.map((g) => g.toString()));
            });
          }
        }
      } catch (_) {
        // Safe fallback: new user starts with empty selection
      }
    }
  }

  void _toggleCategory(String id) {
    setState(() {
      if (_selectedCategories.contains(id)) {
        _selectedCategories.remove(id);
      } else {
        _selectedCategories.add(id);
      }
    });
  }

  Future<void> _skipOnboarding() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id;
    if (userId != null) {
      try {
        // Record profile touch so user is not prompted again in an infinite loop
        await context.read<ManageUserProfileUseCase>().upsertUserProfile(
          userId: userId,
          preferredGenres: _selectedCategories,
          readingFrequency: 2,
          preferredAuthors: [],
          preferredVibe: 'relaxed',
        );
      } catch (_) {}
    }
    if (mounted) {
      context.go('/');
    }
  }

  Future<void> _finishOnboarding() async {
    final auth = context.read<AuthProvider>();
    final recommendationProvider = context.read<RecommendationProvider>();
    final userId = auth.currentUser?.id;
    if (userId == null) {
      context.go('/');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Persist user taste profile (isolated: does not overwrite favorites/reading statuses)
      await context.read<ManageUserProfileUseCase>().upsertUserProfile(
        userId: userId,
        preferredGenres: _selectedCategories,
        readingFrequency: 2,
        preferredAuthors: [],
        preferredVibe: 'relaxed',
      );

      // 2. Submit AI Onboarding signal to calibrate recommender
      final success = await recommendationProvider.submitOnboarding(
        userId: userId,
        bookIds: _selectedBooks,
        genres: _selectedCategories,
      );

      if (mounted) {
        setState(() => _isSaving = false);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('taste_profile_saved')),
              duration: const Duration(seconds: 2),
            ),
          );
          context.go('/');
        } else {
          // Recoverable: offer user to proceed or retry
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('error_loading_books')),
              action: SnackBarAction(
                label: context.tr('retry'),
                onPressed: _finishOnboarding,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('error')}: $e'),
            action: SnackBarAction(
              label: context.tr('retry'),
              onPressed: _finishOnboarding,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.scaffoldBackgroundColor,
              theme.colorScheme.primary.withOpacity(0.06),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(theme, lang),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _buildGenreStep(theme, lang),
                    _buildBookSelectionStep(theme, lang),
                  ],
                ),
              ),
              _buildFooter(theme, lang),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, LanguageProvider lang) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_currentPage > 0)
                TextButton.icon(
                  onPressed: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text(lang.translate('back')),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7)),
                )
              else
                Text(
                  '${context.tr('taste_profile').toUpperCase()} (${_currentPage + 1}/2)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              TextButton(
                onPressed: _skipOnboarding,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                child: Text(
                  context.tr('skip'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (_currentPage + 1) / 2,
              minHeight: 6,
              backgroundColor: theme.colorScheme.onSurface.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTitle(String title, String subtitle, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.65),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildGenreStep(ThemeData theme, LanguageProvider lang) {
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepTitle(
            lang.translate('onboarding_title_1'),
            lang.translate('select_genres_hint'),
            theme,
          ),
          const SizedBox(height: 16),
          if (_selectedCategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                context.tr('ui_selected_count', args: {'count': '${_selectedCategories.length}'}),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategories.contains(cat['id']);
                return InkWell(
                  onTap: () => _toggleCategory(cat['id']!),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary.withOpacity(0.2)
                          : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.white12 : Colors.black12),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(cat['icon']!, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 6),
                        Text(
                          lang.translate('genre_${cat['id']!.toLowerCase().replaceAll('-', '_')}'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookSelectionStep(ThemeData theme, LanguageProvider lang) {
    final searchProvider = context.watch<SearchProvider>();
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepTitle(
            lang.translate('onboarding_title_5'),
            lang.translate('onboarding_subtitle_5'),
            theme,
          ),
          const SizedBox(height: 16),
          TextField(
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: lang.translate('search_hint'),
              prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurface.withOpacity(0.5)),
              filled: true,
              fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
            onChanged: (val) {
              if (val.length > 2) searchProvider.search(val);
            },
          ),
          const SizedBox(height: 12),
          if (_selectedBooks.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedBooks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  return Chip(
                    label: Text('${lang.translate('book')} ${i + 1}', style: const TextStyle(fontSize: 10)),
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() => _selectedBooks.removeAt(i)),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: searchProvider.status == SearchStatus.loading
                ? const Center(child: CircularProgressIndicator())
                : searchProvider.searchResults.isEmpty
                    ? Center(
                        child: Text(
                          lang.translate('search_placeholder'),
                          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: searchProvider.searchResults.length,
                        itemBuilder: (context, i) {
                          final book = searchProvider.searchResults[i];
                          final isSelected = _selectedBooks.contains(book.isbn13);
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                book.coverUrl,
                                height: 40,
                                width: 30,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.book),
                              ),
                            ),
                            title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(book.authorsFormatted, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Checkbox(
                              value: isSelected,
                              activeColor: theme.colorScheme.primary,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedBooks.add(book.isbn13);
                                  } else {
                                    _selectedBooks.remove(book.isbn13);
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, LanguageProvider lang) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _skipOnboarding,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                lang.translate('skip_for_now'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : (_currentPage == 0
                      ? () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          )
                      : _finishOnboarding),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _currentPage == 0
                          ? lang.translate('next').toUpperCase()
                          : lang.translate('finish').toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
