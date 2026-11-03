import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../application/use_cases/process_ai_chat_use_case.dart';
import '../domain/entities/book.dart';
import '../data/models/book_dto.dart';
import '../widgets/book_card.dart';
import '../widgets/saas_widgets.dart';
import '../providers/language_provider.dart';
import '../theme/design_system.dart';

/// Message model for multi-turn AI chat thread.
class AiChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final List<Book> referencedBooks;
  final bool isError;
  final DateTime timestamp;

  const AiChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.referencedBooks = const [],
    this.isError = false,
    required this.timestamp,
  });
}

class AiDiscoveryScreen extends StatefulWidget {
  const AiDiscoveryScreen({super.key});

  @override
  State<AiDiscoveryScreen> createState() => _AiDiscoveryScreenState();
}

class _AiDiscoveryScreenState extends State<AiDiscoveryScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<AiChatMessage> _messages = [];
  bool _isLoading = false;

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

    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();

    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    setState(() {
      _isLoading = true;
      _messages.add(AiChatMessage(
        id: 'u_$messageId',
        isUser: true,
        text: query,
        timestamp: DateTime.now(),
      ));
    });

    _controller.clear();
    _scrollToBottom();

    try {
      final res = await context.read<ProcessAiChatUseCase>().execute(query);
      if (!mounted) return;

      if (res['error'] != null) {
        final errText = res['error'].toString();
        setState(() {
          _messages.add(AiChatMessage(
            id: 'e_$messageId',
            isUser: false,
            text: errText,
            isError: true,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
        return;
      }

      final rawAnswer = res['answer'];
      final trimmedAnswer = rawAnswer is String ? rawAnswer.trim() : '';

      List<Book> books = [];
      if (res['referenced_books'] != null) {
        books = (res['referenced_books'] as List)
            .map((b) => BookDto.fromJson(b as Map<String, dynamic>))
            .toList();
      }

      setState(() {
        _messages.add(AiChatMessage(
          id: 'a_$messageId',
          isUser: false,
          text: trimmedAnswer.isNotEmpty
              ? trimmedAnswer
              : context.read<LanguageProvider>().translate('no_response'),
          referencedBooks: books,
          timestamp: DateTime.now(),
        ));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final errStr = context.read<LanguageProvider>().translate('ai_discovery_error');
      setState(() {
        _messages.add(AiChatMessage(
          id: 'err_$messageId',
          isUser: false,
          text: errStr,
          isError: true,
          timestamp: DateTime.now(),
        ));
      });
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
                child: _messages.isNotEmpty
                    ? _buildResults(theme, isDark)
                    : _buildEmptyState(theme, isDark),
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
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withOpacity(0.2),
                  theme.colorScheme.primary.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(Icons.auto_awesome, size: 48, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: DesignSystem.spacing24),
          Text(
            context.tr('ai_discovery_empty_title'),
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignSystem.spacing12),
          Text(
            context.tr('ai_discovery_empty_subtitle'),
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
              context.tr('ai_try_asking'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: DesignSystem.spacing16),
          ...[
            context.tr('ai_prompt_1'),
            context.tr('ai_prompt_2'),
            context.tr('ai_prompt_3'),
            context.tr('ai_prompt_4'),
          ].map((prompt) => _buildPromptPill(prompt, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildPromptPill(String prompt, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSystem.spacing12),
      child: Material(
        color: isDark ? DesignSystem.saasNavy900 : Colors.white,
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
              border: Border.all(
                color: isDark ? DesignSystem.electricBlueBorder.withOpacity(0.35) : Colors.black12,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    prompt,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 16, color: isDark ? DesignSystem.electricBlue : theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: DesignSystem.spacing16),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildLoadingBubble(theme, isDark);
        }
        final message = _messages[index];
        if (message.isUser) {
          return _buildUserBubble(message, theme, isDark);
        } else {
          return _buildAssistantBubble(message, theme, isDark);
        }
      },
    );
  }

  Widget _buildUserBubble(AiChatMessage message, ThemeData theme, bool isDark) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing8),
        padding: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing16),
        decoration: BoxDecoration(
          color: isDark ? DesignSystem.saasNavy700 : theme.colorScheme.primary,
          border: isDark ? Border.all(color: DesignSystem.electricBlueBorder.withOpacity(0.5)) : null,
          boxShadow: DesignSystem.shadowSm(isDark),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          message.text,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500, height: 1.45),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(AiChatMessage message, ThemeData theme, bool isDark) {
    if (message.isError) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing8),
        padding: const EdgeInsets.all(DesignSystem.spacing20),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withOpacity(0.1),
          borderRadius: DesignSystem.borderRadiusLarge,
          border: Border.all(color: theme.colorScheme.error.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message.text,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing8),
      padding: const EdgeInsets.all(DesignSystem.spacing24),
      decoration: BoxDecoration(
        color: isDark ? DesignSystem.saasNavy900 : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
          bottomLeft: Radius.circular(4),
        ),
        border: Border.all(
          color: isDark ? DesignSystem.electricBlueBorder.withOpacity(0.35) : Colors.black12,
        ),
        boxShadow: isDark ? DesignSystem.saasCardShadow(true) : DesignSystem.shadowSm(false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SaasPulseDot(color: DesignSystem.electricBlue, size: 6.5),
              const SizedBox(width: 6),
              Text(
                'AI Insight · Verified',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isDark ? DesignSystem.electricBlue : theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacing16),
          Text(
            message.text,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          if (message.referencedBooks.isNotEmpty) ...[
            const SizedBox(height: DesignSystem.spacing24),
            Text(
              context.tr('referenced_books'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: DesignSystem.spacing12),
            Column(
              children: [
                for (var book in message.referencedBooks)
                  BookListTile(book: book),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingBubble(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: DesignSystem.spacing20, vertical: DesignSystem.spacing8),
      padding: const EdgeInsets.all(DesignSystem.spacing16),
      decoration: BoxDecoration(
        color: isDark ? DesignSystem.surfaceDarkHighlight : Colors.white,
        borderRadius: DesignSystem.borderRadiusLarge,
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            context.tr('analyzing_request'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
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
