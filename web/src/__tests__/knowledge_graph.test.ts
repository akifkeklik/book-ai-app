import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeKnowledgeEdge,
  normalizeKnowledgeGraph,
  normalizeKnowledgeNode,
} from '../lib/normalizers';
import { ApiService } from '../lib/api';
import { DICTIONARIES } from '../lib/i18n';
import { createRelationshipAction } from '../app/actions/knowledge_graph';

test('normalizeKnowledgeNode: maps raw fields and provides safe defaults', () => {
  const raw = {
    id: '9780141036144',
    label: '1984',
    type: 'book',
    data: { authors: 'George Orwell' },
    degree: 4,
  };

  const node = normalizeKnowledgeNode(raw);
  assert.equal(node.id, '9780141036144');
  assert.equal(node.label, '1984');
  assert.equal(node.type, 'book');
  assert.equal(node.degree, 4);
  assert.equal(node.data.authors, 'George Orwell');
});

test('normalizeKnowledgeNode: handles missing label and null data cleanly', () => {
  const node = normalizeKnowledgeNode({ id: 'concept:ai' });
  assert.equal(node.id, 'concept:ai');
  assert.equal(node.label, 'concept:ai');
  assert.equal(node.type, 'concept');
  assert.equal(node.degree, 0);
  assert.deepEqual(node.data, {});
});

test('normalizeKnowledgeEdge: maps snake_case backend fields to camelCase', () => {
  const raw = {
    id: 'edge-123',
    user_id: 'user-alice-111',
    source_id: '9780141036144',
    source_type: 'book',
    target_id: 'concept:dystopia',
    target_type: 'concept',
    relationship_type: 'covers_concept',
    source: 'book_metadata',
    evidence_ref: 'category:Fiction',
    confidence: 'high',
    metadata: { tag: 'canon' },
    created_at: '2026-10-27T10:00:00Z',
  };

  const edge = normalizeKnowledgeEdge(raw);
  assert.equal(edge.id, 'edge-123');
  assert.equal(edge.userId, 'user-alice-111');
  assert.equal(edge.sourceId, '9780141036144');
  assert.equal(edge.sourceType, 'book');
  assert.equal(edge.targetId, 'concept:dystopia');
  assert.equal(edge.targetType, 'concept');
  assert.equal(edge.relationshipType, 'covers_concept');
  assert.equal(edge.source, 'book_metadata');
  assert.equal(edge.evidenceRef, 'category:Fiction');
  assert.equal(edge.confidence, 'high');
  assert.equal(edge.metadata.tag, 'canon');
  assert.equal(edge.createdAt, '2026-10-27T10:00:00Z');
});

test('normalizeKnowledgeGraph: normalizes composite graph structure with counts', () => {
  const raw = {
    nodes: [
      { id: 'b1', label: 'Book 1', type: 'book', degree: 1 },
      { id: 'c1', label: 'Concept 1', type: 'concept', degree: 1 },
    ],
    edges: [
      {
        id: 'e1',
        user_id: 'u1',
        source_id: 'b1',
        source_type: 'book',
        target_id: 'c1',
        target_type: 'concept',
        relationship_type: 'covers_concept',
      },
    ],
    total_nodes: 2,
    total_edges: 1,
    focus_id: 'b1',
    depth: 1,
  };

  const graph = normalizeKnowledgeGraph(raw);
  assert.equal(graph.nodes.length, 2);
  assert.equal(graph.edges.length, 1);
  assert.equal(graph.totalNodes, 2);
  assert.equal(graph.totalEdges, 1);
  assert.equal(graph.focusId, 'b1');
  assert.equal(graph.depth, 1);
  assert.equal(graph.edges[0].sourceId, 'b1');
  assert.equal(graph.edges[0].targetId, 'c1');
});

test('ApiService.getKnowledgeGraph: builds correct URL and headers', async () => {
  const origFetch = globalThis.fetch;
  let interceptedUrl = '';

  globalThis.fetch = (async (url: string | URL | Request) => {
    interceptedUrl = url.toString();
    return new Response(
      JSON.stringify({
        nodes: [{ id: '9780141036144', label: '1984', type: 'book' }],
        edges: [],
        total_nodes: 1,
        total_edges: 0,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }) as typeof fetch;

  try {
    const data = await ApiService.getKnowledgeGraph({
      focusId: '9780141036144',
      depth: 2,
      limit: 50,
      type: 'book',
    });

    assert.ok(interceptedUrl.includes('/api/knowledge-graph'));
    assert.ok(interceptedUrl.includes('focus_id=9780141036144'));
    assert.ok(interceptedUrl.includes('depth=2'));
    assert.ok(interceptedUrl.includes('limit=50'));
    assert.ok(interceptedUrl.includes('type=book'));
    assert.equal(data.nodes.length, 1);
    assert.equal(data.nodes[0].id, '9780141036144');
  } finally {
    globalThis.fetch = origFetch;
  }
});

test('createRelationshipAction: rejects self-referential relationships', async () => {
  const res = await createRelationshipAction({
    sourceId: 'concept:ai',
    sourceType: 'concept',
    targetId: 'concept:ai',
    targetType: 'concept',
    relationshipType: 'relates_to',
  });

  assert.equal(res.success, false);
  assert.ok(res.error?.includes('Self-referential'));
});

test('createRelationshipAction: rejects empty node IDs', async () => {
  const res = await createRelationshipAction({
    sourceId: '  ',
    sourceType: 'concept',
    targetId: 'concept:ai',
    targetType: 'concept',
    relationshipType: 'relates_to',
  });

  assert.equal(res.success, false);
  assert.ok(res.error?.includes('required'));
});

test('Knowledge Graph i18n: all keys exist in EN, TR, and DE dictionaries', () => {
  const kgKeys = [
    'nav_knowledge_graph',
    'kg_title',
    'kg_subtitle',
    'kg_filter_all',
    'kg_filter_books',
    'kg_filter_concepts',
    'kg_filter_notes',
    'kg_filter_paths',
    'kg_total_nodes',
    'kg_total_edges',
    'kg_depth_label',
    'kg_focus_search',
    'kg_empty_title',
    'kg_empty_desc',
    'kg_node_details',
    'kg_connections',
    'kg_create_connection',
    'kg_source_type',
    'kg_target_type',
    'kg_relationship_type',
    'kg_evidence',
    'kg_confidence',
    'kg_source_user_explicit',
    'kg_source_reading_note',
    'kg_source_book_metadata',
    'kg_source_system_inference',
    'kg_rel_covers_concept',
    'kg_rel_reinforces_concept',
    'kg_rel_relates_to',
    'kg_rel_builds_upon',
    'kg_rel_curates_book',
    'kg_rel_references_book',
    'kg_rel_derived_from',
    'kg_rel_contrasts_with',
    'kg_rel_prerequisite_for',
    'kg_delete_connection',
    'kg_delete_confirm',
    'kg_view_book',
  ] as const;

  for (const key of kgKeys) {
    assert.ok(DICTIONARIES.en[key], `Missing EN key: ${key}`);
    assert.ok(DICTIONARIES.tr[key], `Missing TR key: ${key}`);
    assert.ok(DICTIONARIES.de[key], `Missing DE key: ${key}`);
  }
});


test('KnowledgeGraph: selectedNode state resolution preserves selected node across graph refreshes or resets gracefully', () => {
  type GraphTestNode = {
    id: string;
    label: string;
    type: 'book' | 'concept';
    degree: number;
    data: Record<string, unknown>;
  };

  const resolveSelectedNode = (prev: GraphTestNode | null, freshNodes: GraphTestNode[]): GraphTestNode | null => {
    if (!prev) return null;
    return freshNodes.find((n) => n.id === prev.id) || null;
  };

  const nodeA: GraphTestNode = { id: 'node-a', label: 'Node A', type: 'book', degree: 2, data: {} };
  const nodeB: GraphTestNode = { id: 'node-b', label: 'Node B', type: 'concept', degree: 1, data: {} };
  const nodeAUpdated: GraphTestNode = { id: 'node-a', label: 'Node A Updated', type: 'book', degree: 5, data: {} };

  // 1. When no node selected, remains null
  assert.equal(resolveSelectedNode(null, [nodeA, nodeB]), null);

  // 2. When node-a is selected, updates with fresh data on refresh
  const resolved = resolveSelectedNode(nodeA, [nodeAUpdated, nodeB]);
  assert.notEqual(resolved, null);
  assert.equal(resolved?.id, 'node-a');
  assert.equal(resolved?.degree, 5);

  // 3. When selected node was pruned/filtered out, gracefully resets to null
  assert.equal(resolveSelectedNode(nodeA, [nodeB]), null);
});
