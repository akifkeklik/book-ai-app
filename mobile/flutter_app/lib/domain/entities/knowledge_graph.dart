class KnowledgeNode {
  const KnowledgeNode({
    required this.id,
    required this.label,
    required this.type,
    this.data = const {},
    this.degree = 0,
  });

  final String id;
  final String label;
  final String type; // 'book', 'concept', 'note', 'learning_path'
  final Map<String, dynamic> data;
  final int degree;

  factory KnowledgeNode.fromJson(Map<String, dynamic> json) {
    return KnowledgeNode(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'concept',
      data: json['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['data'] as Map)
          : const {},
      degree: (json['degree'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'type': type,
      'data': data,
      'degree': degree,
    };
  }

  KnowledgeNode copyWith({
    String? id,
    String? label,
    String? type,
    Map<String, dynamic>? data,
    int? degree,
  }) {
    return KnowledgeNode(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      data: data ?? this.data,
      degree: degree ?? this.degree,
    );
  }
}

class KnowledgeEdge {
  const KnowledgeEdge({
    this.id,
    required this.userId,
    required this.sourceId,
    required this.sourceType,
    required this.targetId,
    required this.targetType,
    required this.relationshipType,
    this.source = 'user_explicit',
    this.evidenceRef,
    this.confidence = 'high',
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String userId;
  final String sourceId;
  final String sourceType;
  final String targetId;
  final String targetType;
  final String relationshipType;
  final String source; // 'user_explicit', 'reading_note', 'book_metadata', 'system_inference'
  final String? evidenceRef;
  final String confidence; // 'high', 'medium', 'suggested'
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory KnowledgeEdge.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v);
        } catch (_) {}
      }
      return null;
    }

    return KnowledgeEdge(
      id: json['id']?.toString(),
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      sourceId: json['source_id']?.toString() ?? json['sourceId']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? json['sourceType']?.toString() ?? 'concept',
      targetId: json['target_id']?.toString() ?? json['targetId']?.toString() ?? '',
      targetType: json['target_type']?.toString() ?? json['targetType']?.toString() ?? 'concept',
      relationshipType: json['relationship_type']?.toString() ?? json['relationshipType']?.toString() ?? 'relates_to',
      source: json['source']?.toString() ?? 'user_explicit',
      evidenceRef: json['evidence_ref']?.toString() ?? json['evidenceRef']?.toString(),
      confidence: json['confidence']?.toString() ?? 'high',
      metadata: json['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'source_id': sourceId,
      'source_type': sourceType,
      'target_id': targetId,
      'target_type': targetType,
      'relationship_type': relationshipType,
      'source': source,
      if (evidenceRef != null) 'evidence_ref': evidenceRef,
      'confidence': confidence,
      'metadata': metadata,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}

class KnowledgeGraphData {
  const KnowledgeGraphData({
    this.nodes = const [],
    this.edges = const [],
    this.totalNodes = 0,
    this.totalEdges = 0,
    this.focusId,
    this.depth = 1,
  });

  final List<KnowledgeNode> nodes;
  final List<KnowledgeEdge> edges;
  final int totalNodes;
  final int totalEdges;
  final String? focusId;
  final int depth;

  factory KnowledgeGraphData.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'];
    final rawEdges = json['edges'];

    final parsedNodes = rawNodes is List
        ? rawNodes
            .whereType<Map<String, dynamic>>()
            .map((e) => KnowledgeNode.fromJson(e))
            .toList()
        : <KnowledgeNode>[];

    final parsedEdges = rawEdges is List
        ? rawEdges
            .whereType<Map<String, dynamic>>()
            .map((e) => KnowledgeEdge.fromJson(e))
            .toList()
        : <KnowledgeEdge>[];

    return KnowledgeGraphData(
      nodes: parsedNodes,
      edges: parsedEdges,
      totalNodes: (json['total_nodes'] as num?)?.toInt() ?? (json['totalNodes'] as num?)?.toInt() ?? parsedNodes.length,
      totalEdges: (json['total_edges'] as num?)?.toInt() ?? (json['totalEdges'] as num?)?.toInt() ?? parsedEdges.length,
      focusId: json['focus_id']?.toString() ?? json['focusId']?.toString(),
      depth: (json['depth'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
      'total_nodes': totalNodes,
      'total_edges': totalEdges,
      if (focusId != null) 'focus_id': focusId,
      'depth': depth,
    };
  }
}

