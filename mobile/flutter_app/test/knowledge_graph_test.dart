import 'package:flutter_test/flutter_test.dart';

import 'package:book_ai_app/domain/entities/knowledge_graph.dart';
import 'package:book_ai_app/providers/knowledge_graph_provider.dart';
import 'package:book_ai_app/services/api_service.dart';

class FakeKnowledgeGraphApiService implements ApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  KnowledgeGraphData? mockData;
  bool shouldFail = false;
  String currentUserId = 'user-alice';
  int createCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<KnowledgeGraphData?> getKnowledgeGraph({
    String? focusId,
    int? depth,
    int? limit,
    String? type,
    String? relationshipType,
  }) async {
    if (shouldFail) throw Exception('Network error');
    return mockData;
  }

  @override
  Future<KnowledgeEdge?> createKnowledgeRelationship({
    required String sourceId,
    required String sourceType,
    required String targetId,
    required String targetType,
    required String relationshipType,
    String source = 'user_explicit',
    String? evidenceRef,
    String confidence = 'high',
    Map<String, dynamic>? metadata,
  }) async {
    if (shouldFail) throw Exception('Create failed');
    createCallCount++;
    return KnowledgeEdge(
      id: 'edge-$createCallCount',
      userId: currentUserId,
      sourceId: sourceId,
      sourceType: sourceType,
      targetId: targetId,
      targetType: targetType,
      relationshipType: relationshipType,
      source: source,
      evidenceRef: evidenceRef,
      confidence: confidence,
    );
  }

  @override
  Future<bool> deleteKnowledgeRelationship(String relationshipId) async {
    if (shouldFail) throw Exception('Delete failed');
    deleteCallCount++;
    return true;
  }
}

void main() {
  group('KnowledgeGraph Entity Tests', () {
    test('KnowledgeNode JSON serialization & deserialization', () {
      final json = {
        'id': '9780141036144',
        'label': '1984',
        'type': 'book',
        'data': {'authors': 'George Orwell'},
        'degree': 5,
      };

      final node = KnowledgeNode.fromJson(json);
      expect(node.id, '9780141036144');
      expect(node.label, '1984');
      expect(node.type, 'book');
      expect(node.degree, 5);
      expect(node.data['authors'], 'George Orwell');

      final serialized = node.toJson();
      expect(serialized['id'], '9780141036144');
      expect(serialized['degree'], 5);
    });

    test('KnowledgeEdge JSON serialization & deserialization with evidence', () {
      final json = {
        'id': 'edge-999',
        'user_id': 'user-111',
        'source_id': '9780141036144',
        'source_type': 'book',
        'target_id': 'concept:totalitarianism',
        'target_type': 'concept',
        'relationship_type': 'covers_concept',
        'source': 'book_metadata',
        'evidence_ref': 'category:Fiction',
        'confidence': 'high',
        'metadata': {'note': 'core theme'},
        'created_at': '2026-10-27T12:00:00Z',
      };

      final edge = KnowledgeEdge.fromJson(json);
      expect(edge.id, 'edge-999');
      expect(edge.userId, 'user-111');
      expect(edge.sourceId, '9780141036144');
      expect(edge.targetId, 'concept:totalitarianism');
      expect(edge.relationshipType, 'covers_concept');
      expect(edge.source, 'book_metadata');
      expect(edge.evidenceRef, 'category:Fiction');
      expect(edge.confidence, 'high');
      expect(edge.createdAt, isNotNull);

      final outJson = edge.toJson();
      expect(outJson['source_id'], '9780141036144');
      expect(outJson['relationship_type'], 'covers_concept');
    });

    test('KnowledgeGraphData composite JSON parsing', () {
      final json = {
        'nodes': [
          {'id': 'b1', 'label': 'Book 1', 'type': 'book', 'degree': 2},
          {'id': 'c1', 'label': 'Dystopia', 'type': 'concept', 'degree': 2},
        ],
        'edges': [
          {
            'id': 'e1',
            'user_id': 'u1',
            'source_id': 'b1',
            'source_type': 'book',
            'target_id': 'c1',
            'target_type': 'concept',
            'relationship_type': 'covers_concept',
          }
        ],
        'total_nodes': 2,
        'total_edges': 1,
        'focus_id': 'b1',
        'depth': 2,
      };

      final graph = KnowledgeGraphData.fromJson(json);
      expect(graph.nodes.length, 2);
      expect(graph.edges.length, 1);
      expect(graph.totalNodes, 2);
      expect(graph.totalEdges, 1);
      expect(graph.focusId, 'b1');
      expect(graph.depth, 2);
    });
  });

  group('KnowledgeGraphProvider State Management Tests', () {
    late FakeKnowledgeGraphApiService fakeApi;
    late KnowledgeGraphProvider provider;

    const sampleNode = KnowledgeNode(id: 'b1', label: '1984', type: 'book', degree: 1);
    const sampleEdge = KnowledgeEdge(
      id: 'e1',
      userId: 'user-alice',
      sourceId: 'b1',
      sourceType: 'book',
      targetId: 'concept:dystopia',
      targetType: 'concept',
      relationshipType: 'covers_concept',
    );

    setUp(() {
      fakeApi = FakeKnowledgeGraphApiService();
      fakeApi.mockData = const KnowledgeGraphData(
        nodes: [sampleNode, KnowledgeNode(id: 'concept:dystopia', label: 'Dystopia', type: 'concept', degree: 1)],
        edges: [sampleEdge],
        totalNodes: 2,
        totalEdges: 1,
      );
      provider = KnowledgeGraphProvider(apiService: fakeApi);
    });

    test('loadGraph loads nodes and edges cleanly into state', () async {
      expect(provider.nodes, isEmpty);
      expect(provider.isLoading, isFalse);

      await provider.loadGraph();

      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
      expect(provider.totalNodes, 2);
      expect(provider.totalEdges, 1);
      expect(provider.nodes.first.id, 'b1');
    });

    test('selectNode updates active selected entity', () async {
      await provider.loadGraph();
      expect(provider.selectedNode, isNull);

      provider.selectNode(sampleNode);
      expect(provider.selectedNode?.id, 'b1');

      provider.selectNode(null);
      expect(provider.selectedNode, isNull);
    });

    test('filterByType updates state and requests filtered data', () async {
      provider.filterByType('book');
      expect(provider.selectedType, 'book');
    });

    test('setDepth updates traversal depth', () async {
      provider.setDepth(2);
      expect(provider.depth, 2);
    });

    test('setFocus updates focus node', () async {
      provider.setFocus('concept:dystopia');
      expect(provider.focusId, 'concept:dystopia');
    });

    test('createRelationship calls api and reloads graph', () async {
      await provider.loadGraph();
      final ok = await provider.createRelationship(
        sourceId: 'b1',
        sourceType: 'book',
        targetId: 'concept:surveillance',
        targetType: 'concept',
        relationshipType: 'covers_concept',
      );

      expect(ok, isTrue);
      expect(fakeApi.createCallCount, 1);
    });

    test('deleteRelationship optimistically removes edge from state', () async {
      await provider.loadGraph();
      expect(provider.totalEdges, 1);

      final ok = await provider.deleteRelationship('e1');
      expect(ok, isTrue);
      expect(fakeApi.deleteCallCount, 1);
      expect(provider.totalEdges, 0);
    });

    test('account isolation: updateUser wipes all cached state on logout', () async {
      provider.updateUser('user-alice');
      await provider.loadGraph();
      provider.selectNode(sampleNode);
      provider.setFocus('b1');

      expect(provider.totalNodes, 2);
      expect(provider.selectedNode, isNotNull);

      // User logs out
      provider.updateUser(null);

      expect(provider.graphData, isNull);
      expect(provider.selectedNode, isNull);
      expect(provider.focusId, isNull);
      expect(provider.totalNodes, 0);
      expect(provider.totalEdges, 0);
    });
  });
}
