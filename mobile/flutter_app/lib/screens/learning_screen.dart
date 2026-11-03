import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/learning_provider.dart';
import '../providers/language_provider.dart';
import '../widgets/saas_widgets.dart';
import '../theme/design_system.dart';

class LearningScreen extends StatefulWidget {
  const LearningScreen({super.key});

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen>
    with SingleTickerProviderStateMixin {
  String? _currentUserId;
  late TabController _tabController;
  final TextEditingController _draftResponseController = TextEditingController();
  bool _isAnswerRevealed = false;
  String? _lastFeedback;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final uid = auth.currentUser?.id;
      _currentUserId = uid;
      context.read<LearningProvider>().updateUser(uid);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.id;
    if (uid != _currentUserId) {
      _currentUserId = uid;
      context.read<LearningProvider>().updateUser(uid);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _draftResponseController.dispose();
    super.dispose();
  }

  void _resetCardState() {
    setState(() {
      _isAnswerRevealed = false;
      _draftResponseController.clear();
    });
  }

  Color _getMasteryColor(String level, bool isDark) {
    switch (level) {
      case 'mastered':
        return isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
      case 'proficient':
        return Colors.blue;
      case 'practicing':
        return Colors.amber.shade700;
      case 'novice':
        return Colors.orange;
      case 'insufficient_data':
      default:
        return isDark ? Colors.grey.shade600 : Colors.grey.shade500;
    }
  }

  String _getMasteryLevelLabel(BuildContext context, String level) {
    switch (level) {
      case 'mastered':
        return context.tr('mastery_level_mastered');
      case 'proficient':
        return context.tr('mastery_level_proficient');
      case 'practicing':
        return context.tr('mastery_level_practicing');
      case 'novice':
        return context.tr('mastery_level_novice');
      case 'insufficient_data':
      default:
        return context.tr('mastery_level_insufficient_data');
    }
  }

  Color _getReasonColor(String reasonKey, bool isDark) {
    switch (reasonKey) {
      case 'review_overdue':
        return Colors.redAccent;
      case 'previous_incorrect':
        return Colors.deepOrangeAccent;
      case 'learning_path_continuity':
        return Colors.teal;
      case 'concept_practice':
        return Colors.purpleAccent;
      case 'reinforcement_due':
      default:
        return Colors.blueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<LearningProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr('learning_title'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: context.tr('create_question_button'),
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _showCreateQuestionDialog(context, provider),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => provider.loadAll(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          tabs: [
            Tab(
              icon: const Icon(Icons.psychology_outlined, size: 20),
              text: context.tr('active_recall_title'),
            ),
            Tab(
              icon: const Icon(Icons.warning_amber_rounded, size: 20),
              text: context.tr('difficult_concepts_title'),
            ),
            Tab(
              icon: const Icon(Icons.history_rounded, size: 20),
              text: context.tr('recent_activity_title'),
            ),
          ],
        ),
      ),
      body: provider.isLoading && provider.queue.isEmpty && provider.progress == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMetricsHeader(context, provider, isDark),
                if (_lastFeedback != null)
                  _buildFeedbackBanner(context, isDark),
                if (provider.selectedConceptFilter != null)
                  _buildConceptFilterChip(context, provider),
                if (provider.selectedPathFilter != null)
                  _buildPathFilterChip(context, provider),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActiveRecallView(context, provider, isDark),
                      _buildDifficultConceptsView(context, provider, isDark),
                      _buildRecentHistoryView(context, provider, isDark),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFeedbackBanner(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? const Color(0xFF132A1C) : const Color(0xFFE8F5E9),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _lastFeedback!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _lastFeedback = null),
            child: Icon(Icons.close_rounded,
                size: 16,
                color: isDark ? Colors.white70 : Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildPathFilterChip(BuildContext context, LearningProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.secondary.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.alt_route_rounded, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${context.tr('filter_by_path')}: ${provider.selectedPathFilter}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => provider.filterByPath(null),
            child: const Text('Clear Filter', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildConceptFilterChip(BuildContext context, LearningProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${provider.selectedConceptFilter}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => provider.filterByConcept(null),
            child: const Text('Clear Filter', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsHeader(
      BuildContext context, LearningProvider provider, bool isDark) {
    final theme = Theme.of(context);
    final mastery = provider.masteryScore;
    final level = provider.masteryLevel;
    final levelColor = _getMasteryColor(level, isDark);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DesignSystem.saasNavy900 : const Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('mastery_score'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${mastery.toStringAsFixed(0)}%',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: levelColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: levelColor.withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            _getMasteryLevelLabel(context, level),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: levelColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (provider.activeStreakDays > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 4),
                      Text(
                        '${provider.activeStreakDays}d',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMiniMetric(
                context,
                label: context.tr('reviews_due'),
                value: '${provider.reviewsDue}',
                icon: Icons.access_time_rounded,
                color: Colors.amber.shade700,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildMiniMetric(
                context,
                label: context.tr('reviews_completed'),
                value: '${provider.reviewsCompleted}',
                icon: Icons.done_all_rounded,
                color: Colors.teal,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildMiniMetric(
                context,
                label: context.tr('retention_rate'),
                value: '${provider.retentionRate.toStringAsFixed(0)}%',
                icon: Icons.trending_up_rounded,
                color: Colors.blue,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── 7-Day Activity Chart ───────────────────────────────
          const SaasActivityChart(
            heights: [0.6, 0.85, 0.45, 0.9, 0.7, 1.0, 0.8],
            labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
            activeDayIndex: 5,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: isDark ? Colors.white54 : Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.tr('domain_integrity_disclaimer'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? DesignSystem.saasNavy800 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
          ),
          boxShadow: DesignSystem.shadowSm(isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : DesignSystem.textLightPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRecallView(
      BuildContext context, LearningProvider provider, bool isDark) {
    final theme = Theme.of(context);
    final item = provider.activeItem;

    if (item == null || provider.queue.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  size: 48,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                context.tr('empty_queue_title'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('empty_queue_desc'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tr('create_question_button')),
                onPressed: () => _showCreateQuestionDialog(context, provider),
              ),
            ],
          ),
        ),
      );
    }

    final reasonColor = _getReasonColor(item.recommendationReasonKey, isDark);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header badges: Concept, Stage, Reason
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.concept,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  context.tr('stage_label', args: {'stage': '${item.stage}'}),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: reasonColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: reasonColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 12, color: reasonColor),
                    const SizedBox(width: 4),
                    Text(
                      context.tr(item.recommendationReasonKey),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: reasonColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (item.bookTitle != null && item.bookTitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '📖 ${item.bookTitle}${item.bookAuthor != null ? ' · ${item.bookAuthor}' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Question Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E222B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      item.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Text(
                  item.question,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 17,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // User draft response input
          TextField(
            controller: _draftResponseController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: context.tr('your_answer_placeholder'),
              hintStyle: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
              filled: true,
              fillColor: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),

          const SizedBox(height: 16),

          // Reveal / Hide Answer button
          Center(
            child: OutlinedButton.icon(
              icon: Icon(
                _isAnswerRevealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              label: Text(
                _isAnswerRevealed
                    ? context.tr('hide_answer')
                    : context.tr('reveal_answer'),
              ),
              onPressed: () {
                setState(() => _isAnswerRevealed = !_isAnswerRevealed);
              },
            ),
          ),

          // Revealed Answer & Feedback
          if (_isAnswerRevealed) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF132A1C) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.green.shade800 : const Color(0xFFBBF7D0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 18, color: Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('question_answer_label'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.answer,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.explanation.isNotEmpty) ...[
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.menu_book_rounded,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          context.tr('source_evidence'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.explanation,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Self-assessment action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepOrange,
                      side: const BorderSide(color: Colors.deepOrange),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(
                      context.tr('outcome_struggled'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: provider.isSubmitting
                        ? null
                        : () => _handleOutcome(provider, item.id, 'struggled'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      context.tr('outcome_remembered'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: provider.isSubmitting
                        ? null
                        : () => _handleOutcome(provider, item.id, 'remembered'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleOutcome(
      LearningProvider provider, String itemId, String outcome) async {
    final responseText = _draftResponseController.text.trim();
    final res = await provider.submitAttempt(
      itemId: itemId,
      outcome: outcome,
      responseText: responseText,
    );

    if (!mounted) return;

    if (res != null) {
      final schedule = res['schedule'] as Map<String, dynamic>?;
      final days = schedule?['interval_days'] ?? 1;
      final stage = schedule?['stage'] ?? 1;
      final outcomeLabel = outcome == 'remembered'
          ? context.tr('outcome_remembered')
          : context.tr('outcome_struggled');

      setState(() {
        _lastFeedback = '$outcomeLabel! Stage $stage · Next review in $days days.';
      });
      _resetCardState();
    }
  }

  Widget _buildDifficultConceptsView(
      BuildContext context, LearningProvider provider, bool isDark) {
    final theme = Theme.of(context);
    final concepts = provider.difficultConcepts;

    if (concepts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_rounded, size: 48, color: Colors.teal),
              const SizedBox(height: 16),
              Text(
                context.tr('difficult_concepts_empty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: concepts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final c = concepts[index];
        return Card(
          elevation: 0,
          color: isDark ? const Color(0xFF1E222B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.psychology_alt_rounded,
                      color: Colors.amber, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.concept,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${c.totalAttempts} attempts · ${c.retentionRate.toStringAsFixed(0)}% retention · ${c.dueItems} due',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    provider.filterByConcept(c.concept);
                    _tabController.animateTo(0);
                  },
                  child: Text(
                    context.tr('view_concept_reviews'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentHistoryView(
      BuildContext context, LearningProvider provider, bool isDark) {
    final theme = Theme.of(context);
    final history = provider.recentActivity;

    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.history_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                context.tr('recent_activity_empty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final a = history[index];
        final isSuccess = a.outcome == 'remembered';

        return Card(
          elevation: 0,
          color: isDark ? const Color(0xFF1E222B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            leading: Icon(
              isSuccess
                  ? Icons.check_circle_rounded
                  : Icons.replay_circle_filled_rounded,
              color: isSuccess ? const Color(0xFF16A34A) : Colors.deepOrange,
            ),
            title: Text(
              a.itemTitle ?? a.concept ?? 'Review Attempt',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              '${isSuccess ? context.tr('outcome_remembered') : context.tr('outcome_struggled')} · Stage ${a.stageBefore} → ${a.stageAfter}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            trailing: a.reviewedAt != null
                ? Text(
                    '${a.reviewedAt!.month}/${a.reviewedAt!.day}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _showCreateQuestionDialog(
      BuildContext context, LearningProvider provider) async {
    final titleCtrl = TextEditingController();
    final conceptCtrl = TextEditingController();
    final questionCtrl = TextEditingController();
    final answerCtrl = TextEditingController();
    final explanationCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(dialogCtx.tr('create_question_title')),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: dialogCtx.tr('question_title_label'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: conceptCtrl,
                    decoration: InputDecoration(
                      labelText: dialogCtx.tr('question_concept_label'),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: questionCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: dialogCtx.tr('question_prompt_label'),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: answerCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: dialogCtx.tr('question_answer_label'),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: explanationCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: dialogCtx.tr('question_explanation_label'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  await provider.createQuestion(
                    title: titleCtrl.text.trim().isEmpty
                        ? questionCtrl.text.trim()
                        : titleCtrl.text.trim(),
                    concept: conceptCtrl.text.trim(),
                    question: questionCtrl.text.trim(),
                    answer: answerCtrl.text.trim(),
                    explanation: explanationCtrl.text.trim().isNotEmpty
                        ? explanationCtrl.text.trim()
                        : null,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                }
              },
              child: Text(dialogCtx.tr('save_question_button')),
            ),
          ],
        );
      },
    );
  }
}


