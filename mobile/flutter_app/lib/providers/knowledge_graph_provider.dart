import 'package:flutter/foundation.dart';
import '../domain/entities/knowledge_graph.dart';
import '../services/api_service.dart';

class KnowledgeGraphProvider extends ChangeNotifier {
  KnowledgeGraphProvider({ApiService? apiService})
      : _api = apiService ?? ApiService.instance;

  final ApiService _api;

  KnowledgeGraphData? _graphData;
  KnowledgeNode? _selectedNode;
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;
  String _selectedType = 'all';
  int _depth = 1;
  String? _focusId;

  // Getters
  KnowledgeGraphData? get graphData => _graphData;
  KnowledgeNode? get selectedNode => _selectedNode;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedType => _selectedType;
  int get depth => _depth;
  String? get focusId => _focusId;

  List<KnowledgeNode> get nodes => _graphData?.nodes ?? const [];
  List<KnowledgeEdge> get edges => _graphData?.edges ?? const [];
  int get totalNodes => _graphData?.totalNodes ?? 0;
  int get totalEdges => _graphData?.totalEdges ?? 0;

  /// Account isolation: clears memory state on logout or account switch.
  void updateUser(String? newUserId) {
    if (_currentUserId != newUserId) {
      _currentUserId = newUserId;
      _graphData = null;
      _selectedNode = null;
      _error = null;
      _focusId = null;
      notifyListeners();

      if (newUserId != null && newUserId.isNotEmpty) {
        loadGraph();
      }
    }
  }

  void selectNode(KnowledgeNode? node) {
    _selectedNode = node;
    notifyListeners();
  }

  void filterByType(String type) {
    if (_selectedType != type) {
      _selectedType = type;
      notifyListeners();
      loadGraph();
    }
  }

  void setDepth(int depth) {
    if (_depth != depth && depth >= 1 && depth <= 3) {
      _depth = depth;
      notifyListeners();
      loadGraph();
    }
  }

  void setFocus(String? focusId) {
    _focusId = focusId;
    notifyListeners();
    loadGraph();
  }

  Future<void> loadGraph() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _api.getKnowledgeGraph(
        focusId: _focusId,
        depth: _depth,
        limit: 120,
        type: _selectedType != 'all' ? _selectedType : null,
      );

      if (res != null) {
        _graphData = res;
        // Keep selected node updated if still in graph
        if (_selectedNode != null) {
          final matched = res.nodes.where((n) => n.id == _selectedNode!.id).firstOrNull;
          _selectedNode = matched;
        }
      } else {
        _error = 'Failed to load personal knowledge graph';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createRelationship({
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
    try {
      final created = await _api.createKnowledgeRelationship(
        sourceId: sourceId,
        sourceType: sourceType,
        targetId: targetId,
        targetType: targetType,
        relationshipType: relationshipType,
        source: source,
        evidenceRef: evidenceRef,
        confidence: confidence,
        metadata: metadata,
      );

      if (created != null) {
        await loadGraph();
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteRelationship(String relationshipId) async {
    try {
      // Optimistic edge removal
      if (_graphData != null) {
        final updatedEdges = _graphData!.edges.where((e) => e.id != relationshipId).toList();
        _graphData = KnowledgeGraphData(
          nodes: _graphData!.nodes,
          edges: updatedEdges,
          totalNodes: _graphData!.totalNodes,
          totalEdges: updatedEdges.length,
          focusId: _graphData!.focusId,
          depth: _graphData!.depth,
        );
        notifyListeners();
      }

      final success = await _api.deleteKnowledgeRelationship(relationshipId);
      if (!success) {
        await loadGraph();
        return false;
      }
      return true;
    } catch (e) {
      _error = e.toString();
      await loadGraph();
      return false;
    }
  }
}

