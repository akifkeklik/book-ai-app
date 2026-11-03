import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/entities/knowledge_graph.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/knowledge_graph_provider.dart';

class KnowledgeGraphScreen extends StatefulWidget {
  const KnowledgeGraphScreen({super.key});

  @override
  State<KnowledgeGraphScreen> createState() => _KnowledgeGraphScreenState();
}

class _KnowledgeGraphScreenState extends State<KnowledgeGraphScreen> {
  String? _currentUserId;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final uid = auth.currentUser?.id;
      _currentUserId = uid;
      context.read<KnowledgeGraphProvider>().updateUser(uid);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.id;
    if (uid != _currentUserId) {
      _currentUserId = uid;
      context.read<KnowledgeGraphProvider>().updateUser(uid);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getNodeTypeColor(String type, bool isDark) {
    switch (type) {
      case 'book':
        return Colors.blueAccent;
      case 'concept':
        return Colors.purpleAccent;
      case 'note':
        return Colors.amber;
      case 'learning_path':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getNodeTypeIcon(String type) {
    switch (type) {
      case 'book':
        return Icons.menu_book_rounded;
      case 'concept':
        return Icons.lightbulb_rounded;
      case 'note':
        return Icons.note_alt_rounded;
      case 'learning_path':
        return Icons.explore_rounded;
      default:
        return Icons.bubble_chart_rounded;
    }
  }

  String _getRelationshipLocalized(BuildContext context, String relType) {
    final key = 'kg_rel_$relType';
    final tr = context.tr(key);
    return tr.isNotEmpty && tr != key ? tr : relType.replaceAll('_', ' ');
  }

  String _getSourceLocalized(BuildContext context, String source) {
    final key = 'kg_source_$source';
    final tr = context.tr(key);
    return tr.isNotEmpty && tr != key ? tr : source.replaceAll('_', ' ');
  }

  void _showNodeDetailSheet(BuildContext context, KnowledgeNode node) {
    final kgProvider = context.read<KnowledgeGraphProvider>();
    kgProvider.selectNode(node);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer<KnowledgeGraphProvider>(
          builder: (context, provider, _) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final currentNode = provider.selectedNode ?? node;
            final connectedEdges = provider.edges.where((e) {
              return e.sourceId == currentNode.id || e.targetId == currentNode.id;
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Node Type Pill & Degree
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getNodeTypeColor(currentNode.type, isDark).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getNodeTypeIcon(currentNode.type),
                                  size: 14,
                                  color: _getNodeTypeColor(currentNode.type, isDark),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  currentNode.type.replaceAll('_', ' ').toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _getNodeTypeColor(currentNode.type, isDark),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'deg: ${currentNode.degree}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Node Title / Label
                      Text(
                        currentNode.label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),

                      // Specific metadata card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (currentNode.type == 'book') ...[
                              if (currentNode.data['authors'] != null)
                                Text(
                                  'Author: ${currentNode.data['authors']}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (currentNode.data['categories'] != null)
                                Text(
                                  'Category: ${currentNode.data['categories']}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  final isbn = currentNode.data['isbn13']?.toString() ?? currentNode.id;
                                  Navigator.of(context).pushNamed(
                                    '/detail',
                                    arguments: isbn,
                                  );
                                },
                                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                label: Text(context.tr('kg_view_book')),
                                style: ElevatedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ] else if (currentNode.type == 'note') ...[
                              Text(
                                '"${currentNode.data['content'] ?? ''}"',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                            ] else if (currentNode.type == 'concept') ...[
                              Text(
                                'Canonical Concept: ${currentNode.data['canonical_name'] ?? currentNode.label}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ] else if (currentNode.type == 'learning_path') ...[
                              Text(
                                'Path Category: ${currentNode.data['category'] ?? 'General'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                'Status: ${currentNode.data['status'] ?? 'active'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Actions: Focus Subgraph & Create Connection
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                provider.setFocus(currentNode.id);
                              },
                              icon: const Icon(Icons.filter_center_focus_rounded, size: 16),
                              label: const Text('Focus (1-Hop)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showCreateConnectionDialog(context, currentNode);
                              },
                              icon: const Icon(Icons.add_link_rounded, size: 16),
                              label: Text(context.tr('kg_create_connection')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Connected Edges List
                      Text(
                        '${context.tr('kg_connections')} (${connectedEdges.length})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),

                      if (connectedEdges.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'No direct edges found in current graph view.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: connectedEdges.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final edge = connectedEdges[index];
                            final isSource = edge.sourceId == currentNode.id;
                            final otherId = isSource ? edge.targetId : edge.sourceId;
                            final otherNode = provider.nodes.where((n) => n.id == otherId).firstOrNull;
                            final otherLabel = otherNode?.label ?? otherId;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[900] : Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _getRelationshipLocalized(context, edge.relationshipType),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      if (edge.id != null)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          color: Colors.redAccent,
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (dCtx) => AlertDialog(
                                                title: Text(context.tr('kg_delete_connection')),
                                                content: Text(context.tr('kg_delete_confirm')),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(dCtx, false),
                                                    child: Text(context.tr('cancel')),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(dCtx, true),
                                                    child: Text(
                                                      context.tr('kg_delete_connection'),
                                                      style: const TextStyle(color: Colors.red),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await provider.deleteRelationship(edge.id!);
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${isSource ? '→ Points to' : '← From'}: $otherLabel',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _getSourceLocalized(context, edge.source),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          edge.confidence,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showCreateConnectionDialog(BuildContext context, KnowledgeNode sourceNode) {
    final provider = context.read<KnowledgeGraphProvider>();
    final availableTargets = provider.nodes.where((n) => n.id != sourceNode.id).toList();

    if (availableTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other entities available to connect to.')),
      );
      return;
    }

    KnowledgeNode selectedTarget = availableTargets.first;
    String relType = 'relates_to';
    final evidenceController = TextEditingController();

    showDialog(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(context.tr('kg_create_connection')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Source: ${sourceNode.label} (${sourceNode.type})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(context.tr('kg_target_type'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<KnowledgeNode>(
                      value: selectedTarget,
                      isExpanded: true,
                      items: availableTargets.map((n) {
                        return DropdownMenuItem(
                          value: n,
                          child: Text('${n.label} (${n.type})', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedTarget = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(context.tr('kg_relationship_type'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: relType,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'relates_to', child: Text('Relates To')),
                        DropdownMenuItem(value: 'covers_concept', child: Text('Covers Concept')),
                        DropdownMenuItem(value: 'reinforces_concept', child: Text('Reinforces Concept')),
                        DropdownMenuItem(value: 'builds_upon', child: Text('Builds Upon')),
                        DropdownMenuItem(value: 'curates_book', child: Text('Curates Book')),
                        DropdownMenuItem(value: 'references_book', child: Text('References Book')),
                        DropdownMenuItem(value: 'derived_from', child: Text('Derived From')),
                        DropdownMenuItem(value: 'contrasts_with', child: Text('Contrasts With')),
                        DropdownMenuItem(value: 'prerequisite_for', child: Text('Prerequisite For')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => relType = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: evidenceController,
                      decoration: InputDecoration(
                        labelText: context.tr('kg_evidence'),
                        hintText: 'e.g. Reader note or chapter reference',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: Text(context.tr('cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(dCtx);
                    final ok = await provider.createRelationship(
                      sourceId: sourceNode.id,
                      sourceType: sourceNode.type,
                      targetId: selectedTarget.id,
                      targetType: selectedTarget.type,
                      relationshipType: relType,
                      evidenceRef: evidenceController.text.trim().isNotEmpty
                          ? evidenceController.text.trim()
                          : null,
                    );
                    if (ok && mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Connection created successfully!')),
                      );
                    }
                  },
                  child: Text(context.tr('save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('kg_title')),
        actions: [
          Consumer<KnowledgeGraphProvider>(
            builder: (context, provider, _) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${provider.totalNodes}N • ${provider.totalEdges}E',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<KnowledgeGraphProvider>().loadGraph(),
          ),
        ],
      ),
      body: Consumer<KnowledgeGraphProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    Text(provider.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.loadGraph(),
                      child: Text(context.tr('retry')),
                    ),
                  ],
                ),
              ),
            );
          }

          final allNodes = provider.nodes;
          final filteredNodes = _searchQuery.trim().isEmpty
              ? allNodes
              : allNodes.where((n) {
                  final q = _searchQuery.toLowerCase();
                  return n.label.toLowerCase().contains(q) || n.id.toLowerCase().contains(q);
                }).toList();

          return Column(
            children: [
              // ── Filter Bar ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[100],
                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type Filters
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('all', context.tr('kg_filter_all'), provider),
                          const SizedBox(width: 6),
                          _buildFilterChip('book', context.tr('kg_filter_books'), provider),
                          const SizedBox(width: 6),
                          _buildFilterChip('concept', context.tr('kg_filter_concepts'), provider),
                          const SizedBox(width: 6),
                          _buildFilterChip('note', context.tr('kg_filter_notes'), provider),
                          const SizedBox(width: 6),
                          _buildFilterChip('learning_path', context.tr('kg_filter_paths'), provider),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Depth & Search Row
                    Row(
                      children: [
                        // Depth toggles
                        Text(
                          '${context.tr('kg_depth')}:',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        ...[1, 2, 3].map((d) {
                          final isCurrent = provider.depth == d;
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: InkWell(
                              onTap: () => provider.setDepth(d),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isCurrent
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  '$d',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent ? Colors.white : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: 12),

                        // Search Field
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) => setState(() => _searchQuery = val),
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: context.tr('kg_search_hint'),
                                hintStyle: const TextStyle(fontSize: 12),
                                prefixIcon: const Icon(Icons.search, size: 16),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Active Focus Pill
                    if (provider.focusId != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Focused: ${provider.focusId}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => provider.setFocus(null),
                                  child: const Icon(Icons.close, size: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ── Node Grid / Cluster ──
              Expanded(
                child: filteredNodes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bubble_chart_outlined,
                                size: 54,
                                color: Colors.grey.withOpacity(0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                context.tr('kg_empty_title'),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.tr('kg_empty_desc'),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredNodes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final node = filteredNodes[index];
                          final nodeColor = _getNodeTypeColor(node.type, isDark);

                          return InkWell(
                            onTap: () => _showNodeDetailSheet(context, node),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[900] : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: nodeColor.withOpacity(0.35)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: nodeColor.withOpacity(0.15),
                                    child: Icon(
                                      _getNodeTypeIcon(node.type),
                                      size: 18,
                                      color: nodeColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          node.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          node.type.replaceAll('_', ' ').toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: nodeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${node.degree} links',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String id, String label, KnowledgeGraphProvider provider) {
    final isSelected = provider.selectedType == id;
    final colorScheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.onPrimary : null,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => provider.filterByType(id),
      selectedColor: colorScheme.primary,
      visualDensity: VisualDensity.compact,
    );
  }
}
