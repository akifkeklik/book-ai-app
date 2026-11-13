'use client';

import React, { useState, useEffect, useCallback, useRef, useTransition, useMemo } from 'react';
import Link from 'next/link';
import type {
  KnowledgeGraphData,
  KnowledgeNode,
  KnowledgeNodeType,
  KnowledgeRelationshipType,
} from '@/types';
import { usePreferences } from '@/components/PreferencesProvider';
import { useAuth } from '@/components/AuthProvider';
import {
  getKnowledgeGraphAction,
  createRelationshipAction,
  deleteRelationshipAction,
} from '@/app/actions/knowledge_graph';
import {
  Network,
  BookOpen,
  Lightbulb,
  FileText,
  Compass,
  Plus,
  Trash2,
  Search,
  RefreshCw,
  X,
  ExternalLink,
  ShieldCheck,
  Layers,
  Filter,
} from 'lucide-react';

export interface KnowledgeGraphViewProps {
  className?: string;
  initialFocusId?: string;
}

export function KnowledgeGraphView({ className = '', initialFocusId }: KnowledgeGraphViewProps) {
  const { t } = usePreferences();
  const { user, loading: authLoading } = useAuth();

  const [graphData, setGraphData] = useState<KnowledgeGraphData>({
    nodes: [],
    edges: [],
    totalNodes: 0,
    totalEdges: 0,
    depth: 1,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Filters & Controls
  const [selectedType, setSelectedType] = useState<string>('all');
  const [depth, setDepth] = useState<number>(1);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [focusId, setFocusId] = useState<string | null>(initialFocusId || null);

  // Selection & Details
  const [selectedNode, setSelectedNode] = useState<KnowledgeNode | null>(null);

  // Create Connection Modal
  const [isConnectModalOpen, setIsConnectModalOpen] = useState(false);
  const [targetNodeId, setTargetNodeId] = useState('');
  const [relationshipType, setRelationshipType] = useState<KnowledgeRelationshipType>('relates_to');
  const [connectionEvidence, setConnectionEvidence] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const [, startTransition] = useTransition();
  const activeRequestRef = useRef<number>(0);

  // Load knowledge graph
  const loadGraph = useCallback(
    async (focusOverride?: string | null) => {
      if (!user) {
        setLoading(false);
        return;
      }
      const requestId = ++activeRequestRef.current;
      setLoading(true);
      setError(null);
      try {
        const activeFocus = focusOverride !== undefined ? focusOverride : focusId;
        const res = await getKnowledgeGraphAction({
          focusId: activeFocus || undefined,
          depth,
          limit: 120,
          type: selectedType !== 'all' ? selectedType : undefined,
        });

        if (activeRequestRef.current !== requestId) return;

        if (res.success && res.data) {
          setGraphData(res.data);
          setSelectedNode((prev) => {
            if (!prev) return null;
            return res.data?.nodes.find((n) => n.id === prev.id) || null;
          });
        } else {
          setError(res.error || 'Failed to load knowledge graph');
        }
      } catch (err: unknown) {
        if (activeRequestRef.current !== requestId) return;
        setError(err instanceof Error ? err.message : 'Error loading graph');
      } finally {
        if (activeRequestRef.current === requestId) {
          setLoading(false);
        }
      }
    },
    [user, focusId, depth, selectedType]
  );

  useEffect(() => {
    let ignore = false;
    if (!authLoading) {
      Promise.resolve().then(() => {
        if (!ignore) {
          loadGraph();
        }
      });
    }
    return () => {
      ignore = true;
      
    };
  }, [authLoading, loadGraph]);

  // Filtered nodes based on local search query
  const filteredNodes = useMemo(() => {
    if (!searchQuery.trim()) return graphData.nodes;
    const q = searchQuery.toLowerCase().trim();
    return graphData.nodes.filter(
      (n) => n.label.toLowerCase().includes(q) || n.id.toLowerCase().includes(q)
    );
  }, [graphData.nodes, searchQuery]);

  // Edges connected to selected node
  const selectedNodeEdges = useMemo(() => {
    if (!selectedNode) return [];
    return graphData.edges.filter(
      (e) => e.sourceId === selectedNode.id || e.targetId === selectedNode.id
    );
  }, [selectedNode, graphData.edges]);

  // Handle Create Connection
  const handleCreateConnection = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedNode || !targetNodeId.trim() || submitting) return;

    const targetNode = graphData.nodes.find((n) => n.id === targetNodeId);
    if (!targetNode) return;

    setSubmitting(true);
    try {
      const res = await createRelationshipAction({
        sourceId: selectedNode.id,
        sourceType: selectedNode.type,
        targetId: targetNode.id,
        targetType: targetNode.type,
        relationshipType,
        source: 'user_explicit',
        evidenceRef: connectionEvidence.trim() || undefined,
        confidence: 'high',
      });

      if (res.success) {
        setIsConnectModalOpen(false);
        setTargetNodeId('');
        setConnectionEvidence('');
        await loadGraph();
      } else {
        alert(res.error || 'Failed to create connection');
      }
    } finally {
      setSubmitting(false);
    }
  };

  // Handle Delete Connection
  const handleDeleteConnection = async (edgeId?: string) => {
    if (!edgeId) return;
    if (!confirm(t('kg_delete_confirm') || 'Are you sure you want to remove this connection?')) {
      return;
    }

    startTransition(async () => {
      // Optimistic update
      setGraphData((prev) => ({
        ...prev,
        edges: prev.edges.filter((e) => e.id !== edgeId),
        totalEdges: Math.max(0, prev.totalEdges - 1),
      }));

      const res = await deleteRelationshipAction(edgeId);
      if (!res.success) {
        await loadGraph();
      }
    });
  };

  const getNodeColor = (type: KnowledgeNodeType) => {
    switch (type) {
      case 'book':
        return {
          bg: 'bg-blue-500/10 dark:bg-blue-900/30',
          border: 'border-blue-500/30 dark:border-blue-400/40',
          text: 'text-blue-700 dark:text-blue-300',
          dot: 'bg-blue-500',
        };
      case 'concept':
        return {
          bg: 'bg-purple-500/10 dark:bg-purple-900/30',
          border: 'border-purple-500/30 dark:border-purple-400/40',
          text: 'text-purple-700 dark:text-purple-300',
          dot: 'bg-purple-500',
        };
      case 'note':
        return {
          bg: 'bg-amber-500/10 dark:bg-amber-900/30',
          border: 'border-amber-500/30 dark:border-amber-400/40',
          text: 'text-amber-700 dark:text-amber-300',
          dot: 'bg-amber-500',
        };
      case 'learning_path':
        return {
          bg: 'bg-emerald-500/10 dark:bg-emerald-900/30',
          border: 'border-emerald-500/30 dark:border-emerald-400/40',
          text: 'text-emerald-700 dark:text-emerald-300',
          dot: 'bg-emerald-500',
        };
      default:
        return {
          bg: 'bg-slate-500/10',
          border: 'border-slate-500/30',
          text: 'text-slate-700 dark:text-slate-300',
          dot: 'bg-slate-500',
        };
    }
  };

  const getNodeIcon = (type: KnowledgeNodeType) => {
    switch (type) {
      case 'book':
        return <BookOpen className="w-4 h-4" />;
      case 'concept':
        return <Lightbulb className="w-4 h-4" />;
      case 'note':
        return <FileText className="w-4 h-4" />;
      case 'learning_path':
        return <Compass className="w-4 h-4" />;
      default:
        return <Network className="w-4 h-4" />;
    }
  };

  const getRelationshipLabel = (relType: string) => {
    const key = (`kg_rel_${relType}`) as unknown as Parameters<typeof t>[0];
    return t(key) || relType.replace(/_/g, ' ');
  };

  const getSourceLabel = (src: string) => {
    const key = (`kg_source_${src}`) as unknown as Parameters<typeof t>[0];
    return t(key) || src.replace(/_/g, ' ');
  };

  return (
    <div className={`space-y-6 ${className}`} data-testid="knowledge-graph-container">
      {/* ── Header & Telemetry ── */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 pb-2 border-b border-border/60">
        <div>
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-xl bg-primary/10 text-primary">
              <Network className="w-6 h-6" />
            </div>
            <h1 className="text-2xl font-bold tracking-tight text-foreground">
              {t('kg_title')}
            </h1>
          </div>
          <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
            {t('kg_subtitle')}
          </p>
        </div>

        {/* Graph Meta Metrics */}
        <div className="flex items-center gap-2">
          <div className="px-3 py-1.5 rounded-lg bg-surface-raised border border-border text-xs font-medium flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
            <span>
              {graphData.totalNodes} {t('kg_total_nodes')}
            </span>
            <span className="text-border">|</span>
            <span>
              {graphData.totalEdges} {t('kg_total_edges')}
            </span>
          </div>

          <button
            onClick={() => loadGraph()}
            disabled={loading}
            aria-label={t('kg_refresh')}
            className="p-2 rounded-lg border border-border hover:bg-surface-raised text-muted-foreground hover:text-foreground transition"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      {/* ── Toolbar: Filters & Depth ── */}
      <div className="flex flex-wrap items-center justify-between gap-3 p-3 rounded-xl bg-surface-raised/60 border border-border">
        {/* Type Filter Pills */}
        <div className="flex flex-wrap items-center gap-1.5" role="tablist">
          {[
            { id: 'all', label: t('kg_filter_all'), icon: <Layers className="w-3.5 h-3.5" /> },
            { id: 'book', label: t('kg_filter_books'), icon: <BookOpen className="w-3.5 h-3.5" /> },
            { id: 'concept', label: t('kg_filter_concepts'), icon: <Lightbulb className="w-3.5 h-3.5" /> },
            { id: 'note', label: t('kg_filter_notes'), icon: <FileText className="w-3.5 h-3.5" /> },
            { id: 'learning_path', label: t('kg_filter_paths'), icon: <Compass className="w-3.5 h-3.5" /> },
          ].map((tab) => (
            <button
              key={tab.id}
              role="tab"
              aria-selected={selectedType === tab.id}
              onClick={() => setSelectedType(tab.id)}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition ${
                selectedType === tab.id
                  ? 'bg-primary text-primary-foreground shadow-sm'
                  : 'bg-surface hover:bg-surface-raised text-muted-foreground hover:text-foreground border border-border'
              }`}
            >
              {tab.icon}
              <span>{tab.label}</span>
            </button>
          ))}
        </div>

        {/* Depth & Search */}
        <div className="flex items-center gap-3">
          {/* Depth selection */}
          <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <span className="font-medium">{t('kg_depth_label')}:</span>
            {[1, 2, 3].map((d) => (
              <button
                key={d}
                onClick={() => setDepth(d)}
                className={`w-7 h-7 rounded-md font-semibold transition ${
                  depth === d
                    ? 'bg-primary/20 text-primary border border-primary/30'
                    : 'bg-surface text-muted-foreground hover:bg-surface-raised border border-border'
                }`}
              >
                {d}
              </button>
            ))}
          </div>

          {/* Search / Filter input */}
          <div className="relative">
            <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t('kg_focus_search')}
              className="pl-8 pr-3 py-1.5 text-xs rounded-lg bg-surface border border-border text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary w-48 transition"
            />
          </div>
        </div>
      </div>

      {/* ── Active Focus Pill (if focus node set) ── */}
      {focusId && (
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-primary/10 border border-primary/20 text-xs text-primary w-fit">
          <span className="font-semibold">{t('kg_focused_on')}</span>
          <span className="font-mono">{focusId}</span>
          <button
            onClick={() => {
              setFocusId(null);
              loadGraph(null);
            }}
            className="hover:text-primary/70 p-0.5 ml-1"
            aria-label={t('kg_clear_focus')}
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {/* ── Error Banner ── */}
      {error && (
        <div className="p-4 rounded-xl bg-destructive/10 border border-destructive/20 text-destructive flex items-center justify-between text-sm">
          <span>{error}</span>
          <button
            onClick={() => loadGraph()}
            className="px-3 py-1 text-xs font-semibold rounded-md bg-destructive text-destructive-foreground hover:opacity-90"
          >
            {t('retry')}
          </button>
        </div>
      )}

      {/* ── Loading State ── */}
      {loading ? (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 animate-pulse py-8">
          <div className="md:col-span-2 h-96 rounded-2xl bg-surface-raised/40 border border-border flex items-center justify-center">
            <Network className="w-12 h-12 text-muted-foreground/30 animate-spin" />
          </div>
          <div className="h-96 rounded-2xl bg-surface-raised/40 border border-border" />
        </div>
      ) : graphData.nodes.length === 0 ? (
        /* ── Empty State ── */
        <div className="py-16 text-center rounded-2xl bg-surface-raised/30 border border-border border-dashed p-8">
          <div className="w-16 h-16 rounded-full bg-primary/10 text-primary mx-auto flex items-center justify-center mb-4">
            <Network className="w-8 h-8" />
          </div>
          <h2 className="text-xl font-bold text-foreground">{t('kg_empty_title')}</h2>
          <p className="text-sm text-muted-foreground max-w-md mx-auto mt-2 mb-6">
            {t('kg_empty_desc')}
          </p>
          <div className="flex items-center justify-center gap-3">
            <Link
              href="/catalog"
              className="px-4 py-2 rounded-xl bg-primary text-primary-foreground text-xs font-semibold hover:opacity-90 transition"
            >
              {t('explore_catalog_cta')}
            </Link>
            <Link
              href="/favorites"
              className="px-4 py-2 rounded-xl bg-surface border border-border text-foreground text-xs font-semibold hover:bg-surface-raised transition"
            >
              {t('nav_library')}
            </Link>
          </div>
        </div>
      ) : (
        /* ── Main Interactive Layout ── */
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
          {/* Interactive Knowledge Cluster Canvas */}
          <div className="lg:col-span-2 rounded-2xl bg-surface-raised/30 border border-border p-6 min-h-[460px] flex flex-col justify-between">
            <div className="flex items-center justify-between pb-4 border-b border-border/40">
              <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                Interactive Knowledge Nodes ({filteredNodes.length})
              </span>
              <span className="text-xs text-muted-foreground">{t('kg_click_hint')}</span>
            </div>

            {/* Nodes Cluster Grid */}
            <div className="flex flex-wrap gap-2.5 py-6 items-center content-center max-h-[500px] overflow-y-auto">
              {filteredNodes.map((node) => {
                const colors = getNodeColor(node.type);
                const isSelected = selectedNode?.id === node.id;
                const isFocused = focusId === node.id;

                return (
                  <button
                    key={node.id}
                    onClick={() => setSelectedNode(node)}
                    className={`group relative flex items-center gap-2 px-3.5 py-2 rounded-xl border text-xs font-medium transition-all transform active:scale-95 ${
                      isSelected
                        ? 'ring-2 ring-primary ring-offset-2 ring-offset-background shadow-md scale-105 z-10 ' +
                          colors.bg +
                          ' ' +
                          colors.border +
                          ' ' +
                          colors.text
                        : isFocused
                        ? 'border-primary bg-primary/10 text-primary shadow-sm'
                        : colors.bg + ' ' + colors.border + ' ' + colors.text + ' hover:scale-102 hover:shadow-sm'
                    }`}
                  >
                    <span className={`w-2 h-2 rounded-full ${colors.dot}`} />
                    <span className="truncate max-w-[180px]">{node.label}</span>
                    <span className="opacity-60 text-[10px] ml-0.5">({node.degree})</span>
                  </button>
                );
              })}
            </div>

            {/* Edge Legend */}
            <div className="pt-4 border-t border-border/40 flex flex-wrap items-center justify-between text-xs text-muted-foreground gap-2">
              <div className="flex items-center gap-4">
                <span className="flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-full bg-blue-500" />
                  {t('kg_type_book')}
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-full bg-purple-500" />
                  {t('kg_type_concept')}
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-full bg-amber-500" />
                  {t('kg_type_note')}
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-full bg-emerald-500" />
                  {t('kg_type_path')}
                </span>
              </div>
            </div>
          </div>

          {/* ── Node Details & Evidence Inspector Drawer ── */}
          <div className="rounded-2xl bg-surface-raised border border-border p-6 space-y-6">
            {selectedNode ? (
              <>
                {/* Node Top Header */}
                <div className="flex items-start justify-between gap-3">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <span
                        className={`inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold uppercase tracking-wider ${
                          getNodeColor(selectedNode.type).bg
                        } ${getNodeColor(selectedNode.type).text}`}
                      >
                        {getNodeIcon(selectedNode.type)}
                        {selectedNode.type.replace('_', ' ')}
                      </span>
                      <span className="text-xs text-muted-foreground font-mono">
                        deg: {selectedNode.degree}
                      </span>
                    </div>
                    <h2 className="text-lg font-bold text-foreground leading-snug">
                      {selectedNode.label}
                    </h2>
                  </div>

                  <button
                    onClick={() => setSelectedNode(null)}
                    aria-label={t('kg_close_inspector')}
                    className="p-1 rounded-lg text-muted-foreground hover:bg-surface transition"
                  >
                    <X className="w-4 h-4" />
                  </button>
                </div>

                {/* Node Metadata Section */}
                <div className="p-3.5 rounded-xl bg-surface border border-border/80 text-xs space-y-2">
                  {selectedNode.type === 'book' && (
                    <>
                      {Boolean(selectedNode.data.authors) && (
                        <div>
                          <span className="text-muted-foreground">{t('kg_author_label')} </span>
                          <span className="font-semibold text-foreground">
                            {String(selectedNode.data.authors)}
                          </span>
                        </div>
                      )}
                      {Boolean(selectedNode.data.categories) && (
                        <div>
                          <span className="text-muted-foreground">{t('kg_category_label')} </span>
                          <span className="font-semibold text-foreground">
                            {String(selectedNode.data.categories)}
                          </span>
                        </div>
                      )}
                      <div className="pt-2">
                        <Link
                          href={`/book/${String(selectedNode.data.isbn13 || selectedNode.id)}`}
                          className="inline-flex items-center gap-1 text-primary hover:underline font-semibold"
                        >
                          {t('kg_view_book')}
                          <ExternalLink className="w-3 h-3 ml-0.5" />
                        </Link>
                      </div>
                    </>
                  )}

                  {selectedNode.type === 'concept' && (
                    <div>
                      <span className="text-muted-foreground">{t('kg_topic_label')} </span>
                      <span className="font-semibold text-foreground">
                        {String(selectedNode.data.canonical_name || selectedNode.label)}
                      </span>
                    </div>
                  )}

                  {selectedNode.type === 'note' && (
                    <div className="space-y-1.5">
                      <div className="flex items-center justify-between text-muted-foreground text-[11px]">
                        <span>Note Type: {String(selectedNode.data.note_type || '')}</span>
                        {Boolean(selectedNode.data.created_at) && (
                          <span>
                            {new Date(String(selectedNode.data.created_at)).toLocaleDateString()}
                          </span>
                        )}
                      </div>
                      <p className="italic text-foreground bg-surface-raised p-2 rounded-lg border border-border/50">
                        &quot;{String(selectedNode.data.content || "")}&quot;
                      </p>
                    </div>
                  )}

                  {selectedNode.type === 'learning_path' && (
                    <div className="space-y-1">
                      <div>
                        <span className="text-muted-foreground">{t('kg_category_label')} </span>
                        <span className="font-semibold text-foreground">
                          {String(selectedNode.data.category || 'General')}
                        </span>
                      </div>
                      <div>
                        <span className="text-muted-foreground">{t('kg_status_label')} </span>
                        <span className="font-semibold text-foreground capitalize">
                          {String(selectedNode.data.status || '')}
                        </span>
                      </div>
                    </div>
                  )}

                  {/* Focus Subgraph Button */}
                  <div className="pt-2 border-t border-border/50 flex items-center justify-between">
                    <button
                      onClick={() => {
                        setFocusId(selectedNode.id);
                        loadGraph(selectedNode.id);
                      }}
                      className="text-xs font-semibold text-primary hover:underline flex items-center gap-1"
                    >
                      <Filter className="w-3 h-3" />
                      {t('kg_focus_subgraph')}
                    </button>
                    <button
                      onClick={() => setIsConnectModalOpen(true)}
                      className="text-xs font-semibold text-foreground hover:text-primary flex items-center gap-1"
                    >
                      <Plus className="w-3 h-3" />
                      {t('kg_create_connection')}
                    </button>
                  </div>
                </div>

                {/* ── Connected Relationships List ── */}
                <div className="space-y-3">
                  <div className="flex items-center justify-between text-xs font-semibold text-muted-foreground">
                    <span>
                      {t('kg_connections')} ({selectedNodeEdges.length})
                    </span>
                  </div>

                  {selectedNodeEdges.length === 0 ? (
                    <p className="text-xs text-muted-foreground italic py-2">
                      {t('kg_no_edges')}
                    </p>
                  ) : (
                    <div className="space-y-2.5 max-h-[320px] overflow-y-auto pr-1">
                      {selectedNodeEdges.map((edge, idx) => {
                        const isSource = edge.sourceId === selectedNode.id;
                        const otherId = isSource ? edge.targetId : edge.sourceId;
                        const otherNode = graphData.nodes.find((n) => n.id === otherId);
                        const otherLabel = otherNode?.label || otherId;

                        return (
                          <div
                            key={edge.id || `${edge.sourceId}-${edge.targetId}-${idx}`}
                            className="p-3 rounded-xl bg-surface border border-border text-xs space-y-2 transition hover:border-primary/40"
                          >
                            <div className="flex items-center justify-between gap-2">
                              <span className="font-semibold text-primary">
                                {getRelationshipLabel(edge.relationshipType)}
                              </span>
                              <div className="flex items-center gap-1.5">
                                <span className="px-1.5 py-0.5 rounded text-[10px] bg-surface-raised font-mono border border-border">
                                  {edge.confidence}
                                </span>
                                {edge.id && (
                                  <button
                                    onClick={() => handleDeleteConnection(edge.id)}
                                    aria-label={t('kg_delete_connection')}
                                    className="p-1 text-muted-foreground hover:text-destructive rounded transition"
                                  >
                                    <Trash2 className="w-3 h-3" />
                                  </button>
                                )}
                              </div>
                            </div>

                            {/* Connected Entity */}
                            <div className="flex items-center justify-between text-muted-foreground">
                              <span>
                                {isSource ? '→ Points to' : '← From'}:{' '}
                                <strong className="text-foreground">{otherLabel}</strong>
                              </span>
                              {otherNode && (
                                <button
                                  onClick={() => setSelectedNode(otherNode)}
                                  className="text-primary hover:underline font-medium text-[11px]"
                                >
                                  {t('kg_inspect')}
                                </button>
                              )}
                            </div>

                            {/* Source & Evidence Snippet */}
                            <div className="flex items-center justify-between text-[11px] text-muted-foreground/80 pt-1 border-t border-border/40">
                              <span className="flex items-center gap-1">
                                <ShieldCheck className="w-3 h-3 text-emerald-500" />
                                {getSourceLabel(edge.source)}
                              </span>
                              {edge.evidenceRef && (
                                <span className="truncate max-w-[120px] italic">
                                  {edge.evidenceRef}
                                </span>
                              )}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              </>
            ) : (
              /* No node selected */
              <div className="py-16 text-center space-y-2">
                <Network className="w-10 h-10 text-muted-foreground/40 mx-auto" />
                <h3 className="text-sm font-semibold text-foreground">
                  {t('kg_node_details')}
                </h3>
                <p className="text-xs text-muted-foreground max-w-xs mx-auto">
                  {t('kg_select_hint')}
                </p>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ── Create Relationship Modal ── */}
      {isConnectModalOpen && selectedNode && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-background/80 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-md p-6 rounded-2xl bg-surface border border-border shadow-xl space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-border">
              <h3 className="text-base font-bold text-foreground">
                {t('kg_create_connection')}
              </h3>
              <button
                onClick={() => setIsConnectModalOpen(false)}
                className="p-1 rounded-lg text-muted-foreground hover:bg-surface-raised"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleCreateConnection} className="space-y-4 text-xs">
              <div>
                <label className="block font-medium text-muted-foreground mb-1">
                  {t('kg_source_selected')}
                </label>
                <div className="p-2.5 rounded-lg bg-surface-raised border border-border font-semibold text-foreground">
                  {selectedNode.label} ({selectedNode.type})
                </div>
              </div>

              <div>
                <label className="block font-medium text-muted-foreground mb-1">
                  {t('kg_target')}
                </label>
                <select
                  value={targetNodeId}
                  onChange={(e) => setTargetNodeId(e.target.value)}
                  required
                  className="w-full p-2.5 rounded-lg bg-surface-raised border border-border text-foreground focus:ring-1 focus:ring-primary focus:outline-none"
                >
                  <option value="">{t('kg_select_target')}</option>
                  {graphData.nodes
                    .filter((n) => n.id !== selectedNode.id)
                    .map((n) => (
                      <option key={n.id} value={n.id}>
                        {n.label} ({n.type})
                      </option>
                    ))}
                </select>
              </div>

              <div>
                <label className="block font-medium text-muted-foreground mb-1">
                  {t('kg_relationship_type')}
                </label>
                <select
                  value={relationshipType}
                  onChange={(e) => setRelationshipType(e.target.value as KnowledgeRelationshipType)}
                  className="w-full p-2.5 rounded-lg bg-surface-raised border border-border text-foreground focus:ring-1 focus:ring-primary focus:outline-none"
                >
                  <option value="relates_to">{t('kg_rel_relates_to')}</option>
                  <option value="covers_concept">{t('kg_rel_covers_concept')}</option>
                  <option value="reinforces_concept">{t('kg_rel_reinforces_concept')}</option>
                  <option value="builds_upon">{t('kg_rel_builds_upon')}</option>
                  <option value="curates_book">{t('kg_rel_curates_book')}</option>
                  <option value="references_book">{t('kg_rel_references_book')}</option>
                  <option value="derived_from">{t('kg_rel_derived_from')}</option>
                  <option value="contrasts_with">{t('kg_rel_contrasts_with')}</option>
                  <option value="prerequisite_for">{t('kg_rel_prerequisite_for')}</option>
                </select>
              </div>

              <div>
                <label className="block font-medium text-muted-foreground mb-1">
                  {t('kg_evidence')} (Optional Note / Snippet)
                </label>
                <input
                  type="text"
                  value={connectionEvidence}
                  onChange={(e) => setConnectionEvidence(e.target.value)}
                  placeholder={t('kg_evidence_hint')}
                  className="w-full p-2.5 rounded-lg bg-surface-raised border border-border text-foreground focus:ring-1 focus:ring-primary focus:outline-none"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2 border-t border-border">
                <button
                  type="button"
                  onClick={() => setIsConnectModalOpen(false)}
                  className="px-4 py-2 rounded-xl text-muted-foreground hover:bg-surface-raised font-semibold"
                >
                  {t('cancel')}
                </button>
                <button
                  type="submit"
                  disabled={submitting || !targetNodeId}
                  className="px-4 py-2 rounded-xl bg-primary text-primary-foreground font-semibold hover:opacity-90 disabled:opacity-50 transition"
                >
                  {submitting ? t('loading') : t('save')}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

