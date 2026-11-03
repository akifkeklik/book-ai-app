import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/entities/learning_path.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/learning_path_provider.dart';
import '../services/api_service.dart';
import 'package:go_router/go_router.dart';
import '../providers/learning_provider.dart';
import '../theme/design_system.dart';

class LearningPathsScreen extends StatefulWidget {
  const LearningPathsScreen({super.key});

  @override
  State<LearningPathsScreen> createState() => _LearningPathsScreenState();
}

class _LearningPathsScreenState extends State<LearningPathsScreen> {
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final uid = auth.currentUser?.id;
      _currentUserId = uid;
      context.read<LearningPathProvider>().updateUser(uid);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.id;
    if (uid != _currentUserId) {
      _currentUserId = uid;
      context.read<LearningPathProvider>().updateUser(uid);
    }
  }

  void _showCreatePathDialog(BuildContext context) {
    final titleController = TextEditingController();
    final categoryController = TextEditingController();
    final descController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(context.tr('create_path')),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: '${context.tr('path_title_label')} *',
                      hintText: 'e.g. Stoicism & Ancient Philosophy',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Title is required';
                      }
                      return null;
                    },
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: categoryController,
                    decoration: InputDecoration(
                      labelText: context.tr('path_category_label'),
                      hintText: 'e.g. Philosophy, Science',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    decoration: InputDecoration(
                      labelText: context.tr('path_desc_label'),
                      hintText: 'Key learning goals...',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(ctx).pop();
                  await context.read<LearningPathProvider>().createPath(
                        title: titleController.text.trim(),
                        category: categoryController.text.trim(),
                        description: descController.text.trim(),
                      );
                }
              },
              child: Text(context.tr('create_path')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateBookStatus(String bookId, String status) async {
    try {
      final auth = context.read<AuthProvider>();
      final provider = context.read<LearningPathProvider>();
      final uid = auth.currentUser?.id;
      if (uid != null) {
        await ApiService.instance.submitFeedback(
          userId: uid,
          bookId: bookId,
          interaction: status,
        );
        if (!mounted) return;
        if (provider.activePath != null) {
          await provider.selectPath(provider.activePath!.id);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LearningPathProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('learning_paths_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.tr('create_path'),
            onPressed: () => _showCreatePathDialog(context),
          ),
        ],
      ),
      body: provider.isLoading && provider.paths.isEmpty
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: () => provider.loadPaths(),
              child: provider.paths.isEmpty
                  ? _buildEmptyState(context)
                  : ListView(
                      padding: const EdgeInsets.all(DesignSystem.spacing16),
                      children: [
                        // Path selector chips
                        _buildPathSelector(context, provider),
                        const SizedBox(height: DesignSystem.spacing16),

                        // Active path content
                        if (provider.activePath != null) ...[
                          _buildPathHeader(context, provider, provider.activePath!),
                          const SizedBox(height: DesignSystem.spacing16),
                          _buildProgressBar(context, provider.activePath!),
                          const SizedBox(height: DesignSystem.spacing16),
                          _buildBooksList(context, provider, provider.activePath!),
                          const SizedBox(height: DesignSystem.spacing24),
                          _buildSuggestionsSection(context, provider),
                        ] else if (provider.isLoadingDetail) ...[
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator.adaptive(),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignSystem.spacing24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.explore_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: DesignSystem.spacing16),
            Text(
              context.tr('path_empty_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('path_empty_desc'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: DesignSystem.spacing24),
            ElevatedButton.icon(
              onPressed: () => _showCreatePathDialog(context),
              icon: const Icon(Icons.add),
              label: Text(context.tr('create_path')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathSelector(BuildContext context, LearningPathProvider provider) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: provider.paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final p = provider.paths[index];
          final isSelected = p.id == provider.activePath?.id;
          return ChoiceChip(
            label: Text(p.title),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                provider.selectPath(p.id);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildPathHeader(
    BuildContext context,
    LearningPathProvider provider,
    LearningPath path,
  ) {
    final isCompleted = path.status == 'completed';

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacing16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  path.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('path_all_completed'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.psychology_outlined, size: 20, color: Colors.purpleAccent),
                tooltip: context.tr('start_path_reviews'),
                onPressed: () {
                  context.read<LearningProvider>().filterByPath(path.id);
                  context.push('/learning');
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                tooltip: context.tr('delete_path'),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(context.tr('delete_path')),
                      content: Text(context.tr('path_confirm_delete')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: Text(context.tr('delete_path')),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await provider.deletePath(path.id);
                  }
                },
              ),
            ],
          ),
          if (path.description != null && path.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              path.description!,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, LearningPath path) {
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacing16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${context.tr('path_progress_label')}: ${path.completedBooks} / ${path.totalBooks} books',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(
                '${path.progressPercent}%',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: path.totalBooks > 0 ? (path.completedBooks / path.totalBooks).clamp(0.0, 1.0) : 0.0,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBooksList(
    BuildContext context,
    LearningPathProvider provider,
    LearningPath path,
  ) {
    if (path.books.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text(
          'No books in this path yet. Add from suggestions below!',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: List.generate(path.books.length, (index) {
        final item = path.books[index];
        final book = item.book;
        final isNext = item.bookId == path.nextBookId;
        final isFinished = item.readingStatus == 'finished';
        final isReading = item.readingStatus == 'reading';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isNext ? Colors.indigo.withAlpha(25) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isNext ? Colors.indigoAccent : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              // Index / Check
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isFinished ? Colors.green.withAlpha(40) : Colors.white10,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: isFinished
                    ? const Icon(Icons.check, size: 16, color: Colors.green)
                    : Text(
                        '${index + 1}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(width: 12),

              // Title and Author
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            book?.title ?? item.bookId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        if (isNext)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigoAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              context.tr('path_next_book'),
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      book?.authors ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),

              // 1-Tap status actions
              if (!isReading && !isFinished)
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 20, color: Colors.indigoAccent),
                  tooltip: 'Start Reading',
                  onPressed: () => _updateBookStatus(item.bookId, 'reading'),
                )
              else if (isReading)
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, size: 20, color: Colors.green),
                  tooltip: 'Complete',
                  onPressed: () => _updateBookStatus(item.bookId, 'finished'),
                ),

              // Move up / down
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 16),
                tooltip: context.tr('move_up'),
                onPressed: index > 0
                    ? () {
                        final ids = path.books.map((b) => b.bookId).toList();
                        final temp = ids[index];
                        ids[index] = ids[index - 1];
                        ids[index - 1] = temp;
                        provider.reorderBooks(path.id, ids);
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 16),
                tooltip: context.tr('move_down'),
                onPressed: index < path.books.length - 1
                    ? () {
                        final ids = path.books.map((b) => b.bookId).toList();
                        final temp = ids[index];
                        ids[index] = ids[index + 1];
                        ids[index + 1] = temp;
                        provider.reorderBooks(path.id, ids);
                      }
                    : null,
              ),

              // Remove
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                tooltip: context.tr('remove_from_path'),
                onPressed: () => provider.removeBook(path.id, item.bookId),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSuggestionsSection(
    BuildContext context,
    LearningPathProvider provider,
  ) {
    if (provider.suggestions.isEmpty) return const SizedBox.shrink();

    final activePath = provider.activePath;
    final existingIds = activePath?.books.map((b) => b.bookId).toSet() ?? {};
    final candidates = provider.suggestions.where((b) => !existingIds.contains(b.isbn13)).toList();

    if (candidates.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Colors.amber),
            const SizedBox(width: 8),
            Text(
              context.tr('suggested_books'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: candidates.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final book = candidates[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          book.authors,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: Text(context.tr('add_to_path'), style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      if (activePath != null) {
                        provider.addBook(activePath.id, book.isbn13);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

