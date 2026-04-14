import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/book_provider.dart';
import '../providers/language_provider.dart';
import '../services/supabase_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Configuration for steps
  final List<String> _selectedCategories = [];
  int _readingFrequency = 2; // Default Medium
  final List<String> _selectedAuthors = [];
  String _selectedVibe = 'relaxed';

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

  final List<String> _vibes = ['relaxed', 'intense', 'adventurous', 'educational'];

  void _toggleCategory(String id) {
    setState(() {
      if (_selectedCategories.contains(id)) {
        _selectedCategories.remove(id);
      } else {
        _selectedCategories.add(id);
      }
    });
  }

  Future<void> _finishOnboarding() async {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;

    try {
      await SupabaseService.instance.upsertUserProfile(
        userId: userId,
        preferredGenres: _selectedCategories,
        readingFrequency: _readingFrequency,
        preferredAuthors: _selectedAuthors,
        preferredVibe: _selectedVibe,
      );
      
      if (mounted) {
        await context.read<BookProvider>().fetchPersonalizedRecs(userId);
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('error')}: $e')),
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
              theme.colorScheme.primary.withOpacity(0.05),
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
                    _buildHabitStep(theme, lang),
                    _buildAuthorStep(theme, lang),
                    _buildVibeStep(theme, lang),
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
    double progress = (_currentPage + 1) / 4;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${context.tr('next').toUpperCase()} ${_currentPage + 1} / 4',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              if (_currentPage > 0)
                TextButton.icon(
                  onPressed: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text(lang.translate('back')),
                  style: TextButton.styleFrom(foregroundColor: Colors.white24),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white10,
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
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white54,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildGenreStep(ThemeData theme, LanguageProvider lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildStepTitle(
            lang.translate('onboarding_title_1'),
            lang.translate('onboarding_subtitle_1'),
            theme,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategories.contains(cat['id']);
                return InkWell(
                  onTap: () => _toggleCategory(cat['id']!),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? theme.colorScheme.primary : theme.cardColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? Colors.transparent : Colors.white10,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(cat['icon']!, style: const TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text(
                          lang.translate('genre_${cat['id']!.toLowerCase().replaceAll('-', '_')}'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.w800,
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

  Widget _buildHabitStep(ThemeData theme, LanguageProvider lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepTitle(
            lang.translate('onboarding_title_2'),
            lang.translate('onboarding_subtitle_2'),
            theme,
          ),
          const SizedBox(height: 48),
          _habitCard(theme, 1, lang.translate('habit_low'), Icons.menu_book_outlined),
          const SizedBox(height: 16),
          _habitCard(theme, 2, lang.translate('habit_medium'), Icons.auto_stories_outlined),
          const SizedBox(height: 16),
          _habitCard(theme, 3, lang.translate('habit_high'), Icons.library_books_rounded),
        ],
      ),
    );
  }

  Widget _habitCard(ThemeData theme, int value, String label, IconData icon) {
    final isSelected = _readingFrequency == value;
    return InkWell(
      onTap: () => setState(() => _readingFrequency = value),
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.white10,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? theme.colorScheme.primary : Colors.white24, size: 32),
            const SizedBox(width: 24),
            Text(label, style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.white54,
            )),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorStep(ThemeData theme, LanguageProvider lang) {
    // Senior Suggestion: Allow user to type favorite authors instead of static list
    final List<String> commonAuthors = ['J.R.R. Tolkien', 'George Orwell', 'Stephen King', 'Virginia Woolf', 'Franz Kafka', 'Fyodor Dostoevsky'];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepTitle(
            lang.translate('onboarding_title_3'),
            lang.translate('onboarding_subtitle_3'),
            theme,
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: commonAuthors.map((author) {
              final isSelected = _selectedAuthors.contains(author);
              return FilterChip(
                label: Text(author),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) _selectedAuthors.add(author);
                    else _selectedAuthors.remove(author);
                  });
                },
                backgroundColor: theme.cardColor.withOpacity(0.3),
                selectedColor: theme.colorScheme.primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          TextField(
            decoration: InputDecoration(
              hintText: context.tr('search_hint'),
              prefixIcon: const Icon(Icons.add),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
            onSubmitted: (val) {
              if (val.isNotEmpty) {
                setState(() => _selectedAuthors.add(val));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVibeStep(ThemeData theme, LanguageProvider lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepTitle(
            lang.translate('onboarding_title_4'),
            lang.translate('onboarding_subtitle_4'),
            theme,
          ),
          const SizedBox(height: 48),
          Expanded(
            child: ListView.builder(
              itemCount: _vibes.length,
              itemBuilder: (context, i) {
                final vibe = _vibes[i];
                final isSelected = _selectedVibe == vibe;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    onTap: () => setState(() => _selectedVibe = vibe),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    tileColor: isSelected ? theme.colorScheme.primary : Colors.white.withOpacity(0.03),
                    title: Text(
                      lang.translate('vibe_$vibe'),
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check, color: Colors.black) : null,
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
    bool canGoNext = true;
    if (_currentPage == 0 && _selectedCategories.length < 3) canGoNext = false;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton(
          onPressed: canGoNext 
            ? (_currentPage < 3 
                ? () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)
                : _finishOnboarding)
            : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white10,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 8,
            shadowColor: theme.colorScheme.primary.withOpacity(0.4),
          ),
          child: Text(
            _currentPage == 3 ? lang.translate('finish').toUpperCase() : lang.translate('next').toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
          ),
        ),
      ),
    );
  }
}
