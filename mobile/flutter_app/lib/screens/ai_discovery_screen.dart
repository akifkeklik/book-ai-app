import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../domain/repositories/book_repository.dart';
import '../domain/entities/book.dart';
import '../data/models/book_dto.dart';
import '../widgets/book_card.dart';
import '../providers/language_provider.dart';
import '../theme/design_system.dart';

class AiDiscoveryScreen extends StatefulWidget {
  const AiDiscoveryScreen({super.key});

  @override
  State<AiDiscoveryScreen> createState() => _AiDiscoveryScreenState();
}

class _AiDiscoveryScreenState extends State<AiDiscoveryScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  String _answer = "";
  List<Book> _referencedBooks = [];
  bool _hasSearched = false;
  String? _error;

  final List<String> _examplePrompts = [
    "I want a fast-paced sci-fi thriller about space exploration",
    "Books similar to Harry Potter but darker",
    "A self-help book about building habits",
    "Historical fiction set in ancient Rome"
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitQuery([String? predefinedQuery]) async {
    if (_isLoading) return;

    final query = predefinedQuery ?? _controller.text.trim();
    if (query.isEmpty) return;

    if (predefinedQuery != null) {
      _controller.text = predefinedQuery;
    }

    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _answer = "";
      _referencedBooks = [];
      _error = null;
    });

    try {
      final res = await context.read<BookRepository>().chatWithAI(query);
      if (!mounted) return;
      setState(() {
        _answer = res['answer'] ?? context.read<LanguageProvider>().translate('no_response');
        if (res['referenced_books'] != null) {
          _referencedBooks = (res['referenced_books'] as List)
              .map((b) => BookDto.fromJson(b as Map<String, dynamic>))
              .toList();
        }
      });
      _scrollToTop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.read<LanguageProvider>().translate('error_loading_books');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ai_insight'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withOpacity(isDark ? 0.1 : 0.05),
              theme.scaffoldBackgroundColor,
            ],
            stops: const [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _hasSearched ? _buildResults(theme, isDark) : _buildEmptyState(theme, isDark),
              ),
              _buildInputArea(theme, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing24, vertical: DesignSystem.spacing32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: DesignSystem.spacing40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withOpacity(0.1),
            ),
            child: Icon(Icons.auto_awesome, size: 48, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: DesignSystem.spacing24),
          Text(
            'Libris AI Discovery',
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignSystem.spacing12),
          Text(
            'Describe exactly what you\'re in the mood for, and our AI will curate the perfect recommendations for you.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark ? Colors.white70 : DesignSystem.textLightSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignSystem.spacing48),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Try asking:',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: DesignSystem.spacing16),
          ..._examplePrompts.map((prompt) => _buildPromptPill(prompt, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildPromptPill(String prompt, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSystem.spacing12),
      child: Material(
        color: isDark ? DesignSystem.surfaceDarkHighlight : Colors.white,
        borderRadius: DesignSystem.borderRadiusLarge,
        elevation: isDark ? 0 : 2,
        shadowColor: Colors.black.withOpacity(0.05),
        child: InkWell(
          borderRadius: DesignSystem.borderRadiusLarge,
          onTap: () => _submitQuery(prompt),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing16),
            decoration: BoxDecoration(
              borderRadius: DesignSystem.borderRadiusLarge,
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    prompt,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 16, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: DesignSystem.spacing24),
            Text(
              'Analyzing your request...',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error.withOpacity(0.8)),
              const SizedBox(height: 24),
              Text(
                _error!,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _submitQuery(),
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('retry')),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: DesignSystem.spacing24),
      children: [
        // Query bubble
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing8),
            padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              _controller.text,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),

        const SizedBox(height: DesignSystem.spacing16),

        // AI Answer bubble
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing8),
            padding: const EdgeInsets.all(DesignSystem.spacing24),
            decoration: BoxDecoration(
              color: isDark ? DesignSystem.surfaceDarkHighlight : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              boxShadow: DesignSystem.shadowSm(isDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'AI Insight',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignSystem.spacing16),
                Text(
                  _answer,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ),

        if (_referencedBooks.isNotEmpty) ...[
          const SizedBox(height: DesignSystem.spacing32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20),
            child: Text(
              context.tr('referenced_books'),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: DesignSystem.spacing16),
          SizedBox(
            height: 310,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20),
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: _referencedBooks.length,
              separatorBuilder: (_, __) => const SizedBox(width: DesignSystem.spacing16),
              itemBuilder: (context, index) {
                return BookCard(book: _referencedBooks[index]);
              },
            ),
          ),
        ]
      ],
    );
  }

  Widget _buildInputArea(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacing16),
      decoration: BoxDecoration(
        color: isDark ? DesignSystem.surfaceDark : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? DesignSystem.surfaceDarkHighlight : DesignSystem.surfaceLightHighlight,
                borderRadius: DesignSystem.borderRadiusLarge,
                border: Border.all(color: isDark ? Colors.transparent : Colors.black12),
              ),
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitQuery(),
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: context.tr('search_hint'),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing16),
                ),
              ),
            ),
          ),
          const SizedBox(width: DesignSystem.spacing12),
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: DesignSystem.shadowSm(isDark),
            ),
            child: IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              onPressed: _isLoading ? null : () => _submitQuery(),
            ),
          ),
        ],
      ),
    );
  }
}
