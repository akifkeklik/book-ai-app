'use client';

import React, { useState, useEffect } from 'react';
import {
  Brain,
  CheckCircle2,
  RotateCcw,
  Flame,
  Plus,
  AlertTriangle,
  ArrowRight,
  TrendingUp,
  History,
  Layers,
  Loader2,
  Sparkles,
  Compass,
} from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import {
  getLearningOverviewAction,
  getLearningQueueAction,
  getLearningHistoryAction,
} from '@/app/actions/learning';
import { ActiveRecallCard } from '@/components/ActiveRecallCard';
import { CreateReviewItemModal } from '@/components/CreateReviewItemModal';
import type { LearningProgress, ReviewAttempt, ReviewItem } from '@/types';

export interface LearningDashboardProps {
  initialProgress?: LearningProgress;
  initialQueue?: ReviewItem[];
  initialHistory?: ReviewAttempt[];
  initialConceptFilter?: string;
  initialPathId?: string;
}

export function LearningDashboard({
  initialProgress,
  initialQueue,
  initialHistory,
  initialConceptFilter,
  initialPathId,
}: LearningDashboardProps) {
  const { t } = usePreferences();
  const [progress, setProgress] = useState<LearningProgress | undefined>(initialProgress);
  const [queue, setQueue] = useState<ReviewItem[]>(initialQueue || []);
  const [history, setHistory] = useState<ReviewAttempt[]>(initialHistory || []);
  const [selectedConcept, setSelectedConcept] = useState<string | undefined>(initialConceptFilter);
  const [selectedPathId, setSelectedPathId] = useState<string | undefined>(initialPathId);
  const [loading, setLoading] = useState<boolean>(!initialProgress || !initialQueue);
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<'queue' | 'difficult' | 'history'>('queue');

  const loadData = async (conceptFilter?: string, pathFilter?: string) => {
    try {
      setLoading(true);
      const [progRes, queueRes, histRes] = await Promise.all([
        getLearningOverviewAction(),
        getLearningQueueAction({ concept: conceptFilter, pathId: pathFilter }),
        getLearningHistoryAction({ limit: 20 }),
      ]);

      if (progRes.success && progRes.progress) {
        setProgress(progRes.progress);
      }
      if (queueRes.success && queueRes.queue) {
        setQueue(queueRes.queue);
      }
      if (histRes.success && histRes.attempts) {
        setHistory(histRes.attempts);
      }
    } catch {
      // Safe fallback
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let ignore = false;
    if (initialProgress && initialQueue && !initialConceptFilter && !initialPathId) return;
    Promise.resolve().then(() => {
      if (!ignore) {
        loadData(selectedConcept, selectedPathId);
      }
    });
    return () => {
      ignore = true;
    };
  }, [selectedConcept, selectedPathId, initialConceptFilter, initialPathId, initialProgress, initialQueue]);

  const handleAttemptSubmitted = (itemId: string) => {
    // Optimistically update queue & refresh progress
    setQueue((prev) => prev.filter((i) => i.id !== itemId));
    // Soft reload stats in background
    getLearningOverviewAction().then((res) => {
      if (res.success && res.progress) setProgress(res.progress);
    });
    getLearningHistoryAction({ limit: 20 }).then((res) => {
      if (res.success && res.attempts) setHistory(res.attempts);
    });
  };

  const handleQuestionCreated = (newItem: ReviewItem) => {
    setQueue((prev) => [newItem, ...prev]);
    setProgress((prev) =>
      prev
        ? {
            ...prev,
            totalItems: prev.totalItems + 1,
            reviewsDue: prev.reviewsDue + 1,
          }
        : prev
    );
  };

  const getMasteryBadge = (level: string) => {
    if (level === 'mastered') {
      return (
        <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-emerald-500/15 text-emerald-600 dark:text-emerald-400">
          {t('mastery_level_mastered')}
        </span>
      );
    }
    if (level === 'proficient') {
      return (
        <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-blue-500/15 text-blue-600 dark:text-blue-400">
          {t('mastery_level_proficient')}
        </span>
      );
    }
    if (level === 'practicing') {
      return (
        <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-purple-500/15 text-purple-600 dark:text-purple-400">
          {t('mastery_level_practicing')}
        </span>
      );
    }
    if (level === 'novice') {
      return (
        <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-amber-500/15 text-amber-600 dark:text-amber-400">
          {t('mastery_level_novice')}
        </span>
      );
    }
    return (
      <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-neutral-500/15 text-neutral-600 dark:text-neutral-400">
        {t('mastery_level_insufficient_data')}
      </span>
    );
  };

  return (
    <div className="space-y-8 pb-12">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2 mb-1.5">
            <div className="w-8 h-8 rounded-xl bg-purple-500/15 text-purple-600 dark:text-purple-400 flex items-center justify-center">
              <Brain className="w-4 h-4" />
            </div>
            <h1 className="text-2xl font-bold tracking-tight text-[var(--text)]">
              {t('learning_title')}
            </h1>
          </div>
          <p className="text-sm text-[var(--text-secondary)]">{t('learning_subtitle')}</p>
        </div>

        <button
          type="button"
          onClick={() => setIsCreateModalOpen(true)}
          className="px-4 py-2.5 rounded-xl bg-[var(--accent)] text-white text-sm font-semibold hover:opacity-90 flex items-center justify-center gap-2 shadow-sm transition-all"
        >
          <Plus className="w-4 h-4" />
          <span>{t('create_question_button')}</span>
        </button>
      </div>

      {/* Top Learning Intelligence Metrics */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3.5">
        {/* Metric 1: Mastery Estimate */}
        <div className="saas-metric-card col-span-2 sm:col-span-1">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('mastery_score')}</span>
            <div className="saas-metric-icon">
              <TrendingUp className="w-4 h-4" />
            </div>
          </div>
          <div className="saas-metric-value">
            {progress?.masteryScore || 0}%
          </div>
          <div className="saas-metric-footer">
            {getMasteryBadge(progress?.masteryLevel || 'insufficient_data')}
          </div>
        </div>

        {/* Metric 2: Reviews Due */}
        <div className="saas-metric-card">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('reviews_due')}</span>
            <div className="saas-metric-icon" style={{ background: 'rgba(192, 132, 252, 0.12)', color: '#c084fc', borderColor: 'rgba(192, 132, 252, 0.28)' }}>
              <RotateCcw className="w-4 h-4" />
            </div>
          </div>
          <div className="saas-metric-value">
            {progress?.reviewsDue ?? 0}
          </div>
          <div className="saas-metric-footer">
            <span className="saas-pulse-dot amber" />
            <span>Active recall ready</span>
          </div>
        </div>

        {/* Metric 3: Completed Reviews */}
        <div className="saas-metric-card">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('reviews_completed')}</span>
            <div className="saas-metric-icon" style={{ background: 'rgba(16, 185, 129, 0.12)', color: '#10b981', borderColor: 'rgba(16, 185, 129, 0.28)' }}>
              <CheckCircle2 className="w-4 h-4" />
            </div>
          </div>
          <div className="saas-metric-value">
            {progress?.reviewsCompleted ?? 0}
          </div>
          <div className="saas-metric-footer">
            <span className="saas-pulse-dot emerald" />
            <span>Retained milestones</span>
          </div>
        </div>

        {/* Metric 4: Retention Rate */}
        <div className="saas-metric-card">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('retention_rate')}</span>
            <div className="saas-metric-icon" style={{ background: 'rgba(56, 189, 248, 0.12)', color: '#38bdf8', borderColor: 'rgba(56, 189, 248, 0.28)' }}>
              <Brain className="w-4 h-4" />
            </div>
          </div>
          <div className="saas-metric-value">
            {Math.round((progress?.retentionRate || 0) * 100)}%
          </div>
          <div className="saas-metric-footer">
            <span className="saas-pulse-dot blue" />
            <span>Memory stability</span>
          </div>
        </div>

        {/* Metric 5: Active Streak */}
        <div className="saas-metric-card">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('active_streak')}</span>
            <div className="saas-metric-icon" style={{ background: 'rgba(245, 158, 11, 0.12)', color: '#f59e0b', borderColor: 'rgba(245, 158, 11, 0.28)' }}>
              <Flame className="w-4 h-4" />
            </div>
          </div>
          <div className="saas-metric-value flex items-center gap-1.5">
            <span>{progress?.activeStreakDays ?? 0}</span>
            <span className="text-xs font-normal text-[var(--text-muted)] font-sans">days</span>
          </div>
          <div className="saas-metric-footer">
            <span className="saas-pulse-dot amber" />
            <span>Daily habit continuity</span>
          </div>
        </div>
      </div>

      {/* ── Mastery & Concept Breakdown Visualization ────────────────── */}
      <div className="saas-glass-panel" style={{ padding: '1.25rem 1.5rem', marginBottom: '1.5rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem', flexWrap: 'wrap', gap: '0.5rem' }}>
          <div>
            <div style={{ fontSize: '0.85rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)' }}>
              Learning Outcomes & Memory Retention Visualizer
            </div>
            <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', marginTop: '2px' }}>
              Dynamic spaced-repetition memory trace and concept stabilization
            </div>
          </div>
          <div style={{ display: 'flex', gap: '1rem', alignItems: 'center', fontSize: '0.75rem' }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: '5px' }}>
              <span className="saas-pulse-dot emerald" style={{ width: '8px', height: '8px' }} /> Mastered
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: '5px' }}>
              <span className="saas-pulse-dot blue" style={{ width: '8px', height: '8px' }} /> Proficient
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: '5px' }}>
              <span className="saas-pulse-dot amber" style={{ width: '8px', height: '8px' }} /> Practicing
            </span>
          </div>
        </div>

        {/* Visual Multi-Segment Bar */}
        <div className="saas-progress-track" style={{ height: '12px', display: 'flex', overflow: 'hidden' }}>
          <div
            title={`Mastered: ${progress?.masteryScore || 0}%`}
            style={{
              width: `${Math.min(progress?.masteryScore || 15, 100)}%`,
              background: 'linear-gradient(90deg, #059669, #10b981)',
              transition: 'width 0.4s ease',
            }}
          />
          <div
            title="Proficient / In Review"
            style={{
              width: `${Math.max(0, Math.min(30, 100 - (progress?.masteryScore || 15)))}%`,
              background: 'linear-gradient(90deg, #0284c7, var(--electric-blue))',
              transition: 'width 0.4s ease',
            }}
          />
          <div
            title="Practicing / Queue"
            style={{
              flex: 1,
              background: 'linear-gradient(90deg, #d97706, #f59e0b)',
            }}
          />
        </div>
      </div>

      {/* Domain Integrity & Transparency Note */}
      <div className="p-3.5 rounded-xl bg-[var(--surface-raised)]/60 border border-[var(--border)] text-xs text-[var(--text-secondary)] flex items-center gap-2.5">
        <Sparkles className="w-4 h-4 text-[var(--accent)] flex-shrink-0" />
        <p className="leading-relaxed">
          {t('domain_integrity_disclaimer')}
        </p>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 border-b border-[var(--border)] pb-1">
        <button
          type="button"
          onClick={() => {
            setActiveTab('queue');
            setSelectedConcept(undefined);
            setSelectedPathId(undefined);
          }}
          className={`px-4 py-2 text-sm font-semibold rounded-t-xl transition-colors flex items-center gap-2 ${
            activeTab === 'queue'
              ? 'border-b-2 border-[var(--accent)] text-[var(--accent)] bg-[var(--surface-raised)]'
              : 'text-[var(--text-secondary)] hover:text-[var(--text)]'
          }`}
        >
          <Layers className="w-4 h-4" />
          <span>{t('active_recall_title')}</span>
          {queue.length > 0 && (
            <span className="text-[11px] font-bold px-2 py-0.5 rounded-full bg-purple-500/15 text-purple-600 dark:text-purple-400">
              {queue.length}
            </span>
          )}
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('difficult')}
          className={`px-4 py-2 text-sm font-semibold rounded-t-xl transition-colors flex items-center gap-2 ${
            activeTab === 'difficult'
              ? 'border-b-2 border-[var(--accent)] text-[var(--accent)] bg-[var(--surface-raised)]'
              : 'text-[var(--text-secondary)] hover:text-[var(--text)]'
          }`}
        >
          <AlertTriangle className="w-4 h-4" />
          <span>{t('difficult_concepts_title')}</span>
          {(progress?.difficultConcepts?.length || 0) > 0 && (
            <span className="text-[11px] font-bold px-2 py-0.5 rounded-full bg-amber-500/15 text-amber-600 dark:text-amber-400">
              {progress?.difficultConcepts.length}
            </span>
          )}
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('history')}
          className={`px-4 py-2 text-sm font-semibold rounded-t-xl transition-colors flex items-center gap-2 ${
            activeTab === 'history'
              ? 'border-b-2 border-[var(--accent)] text-[var(--accent)] bg-[var(--surface-raised)]'
              : 'text-[var(--text-secondary)] hover:text-[var(--text)]'
          }`}
        >
          <History className="w-4 h-4" />
          <span>{t('recent_activity_title')}</span>
        </button>
      </div>

      {/* Selected Concept Filter Chip */}
      {selectedConcept && (
        <div className="flex items-center gap-2 p-2.5 rounded-xl bg-[var(--surface-raised)] border border-[var(--border)] text-xs">
          <span className="text-[var(--text-secondary)]">Filtered by concept:</span>
          <span className="font-bold text-[var(--accent)]">{selectedConcept}</span>
          <button
            type="button"
            onClick={() => setSelectedConcept(undefined)}
            className="ml-auto text-[var(--text-secondary)] hover:text-[var(--text)] font-semibold"
          >
            Clear filter
          </button>
        </div>
      )}

      {/* Selected Path Filter Chip */}
      {selectedPathId && (
        <div className="flex items-center gap-2 p-2.5 rounded-xl bg-[var(--surface-raised)] border border-[var(--border)] text-xs">
          <Compass className="w-3.5 h-3.5 text-[var(--accent)]" />
          <span className="text-[var(--text-secondary)]">{t('filter_by_path')}:</span>
          <span className="font-bold text-[var(--accent)]">{selectedPathId}</span>
          <button
            type="button"
            onClick={() => setSelectedPathId(undefined)}
            className="ml-auto text-[var(--text-secondary)] hover:text-[var(--text)] font-semibold"
          >
            Clear filter
          </button>
        </div>
      )}

      {/* Loading state */}
      {loading && (
        <div className="p-12 text-center flex flex-col items-center justify-center gap-3">
          <Loader2 className="w-6 h-6 animate-spin text-[var(--accent)]" />
          <p className="text-sm text-[var(--text-secondary)]">Loading learning outcomes...</p>
        </div>
      )}

      {/* TAB 1: Review Queue / Active Recall */}
      {!loading && activeTab === 'queue' && (
        <div className="space-y-4">
          {queue.length === 0 ? (
            <div className="p-8 rounded-2xl border border-[var(--border)] bg-[var(--surface)] text-center space-y-3">
              <div className="w-12 h-12 rounded-2xl bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 mx-auto flex items-center justify-center">
                <CheckCircle2 className="w-6 h-6" />
              </div>
              <h3 className="text-base font-bold text-[var(--text)]">
                {t('empty_queue_title')}
              </h3>
              <p className="text-xs text-[var(--text-secondary)] max-w-md mx-auto">
                {t('empty_queue_desc')}
              </p>
              <button
                type="button"
                onClick={() => setIsCreateModalOpen(true)}
                className="mt-2 px-4 py-2 rounded-xl bg-[var(--surface-raised)] border border-[var(--border)] text-xs font-bold text-[var(--text)] hover:bg-[var(--surface)]"
              >
                {t('create_question_button')}
              </button>
            </div>
          ) : (
            <div className="space-y-4">
              {queue.map((item) => (
                <ActiveRecallCard
                  key={item.id}
                  item={item}
                  onAttemptSubmitted={() => handleAttemptSubmitted(item.id)}
                />
              ))}
            </div>
          )}
        </div>
      )}

      {/* TAB 2: Difficult Concepts */}
      {!loading && activeTab === 'difficult' && (
        <div className="space-y-3">
          {(progress?.difficultConcepts?.length || 0) === 0 ? (
            <div className="p-8 rounded-2xl border border-[var(--border)] bg-[var(--surface)] text-center space-y-2">
              <CheckCircle2 className="w-8 h-8 text-emerald-500 mx-auto" />
              <p className="text-sm font-semibold text-[var(--text)]">
                {t('difficult_concepts_empty')}
              </p>
            </div>
          ) : (
            progress?.difficultConcepts.map((c) => (
              <div
                key={c.concept}
                className="p-4 rounded-xl border border-[var(--border)] bg-[var(--surface)] flex flex-col sm:flex-row sm:items-center justify-between gap-3"
              >
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-bold text-[var(--text)]">{c.concept}</span>
                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-500/15 text-amber-600 dark:text-amber-400">
                      {c.struggledRecalls} struggles
                    </span>
                  </div>
                  <p className="text-xs text-[var(--text-secondary)]">
                    {c.totalItems} items • {Math.round(c.retentionRate * 100)}% retention • Avg stage {c.averageStage}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedConcept(c.concept);
                    setActiveTab('queue');
                  }}
                  className="px-3.5 py-2 rounded-xl bg-[var(--surface-raised)] border border-[var(--border)] text-xs font-bold text-[var(--accent)] hover:bg-[var(--surface)] flex items-center justify-center gap-1.5 self-start sm:self-auto"
                >
                  <span>{t('view_concept_reviews')}</span>
                  <ArrowRight className="w-3.5 h-3.5" />
                </button>
              </div>
            ))
          )}
        </div>
      )}

      {/* TAB 3: Recent Activity History */}
      {!loading && activeTab === 'history' && (
        <div className="space-y-3">
          {history.length === 0 ? (
            <div className="p-8 rounded-2xl border border-[var(--border)] bg-[var(--surface)] text-center">
              <p className="text-sm text-[var(--text-secondary)]">
                {t('recent_activity_empty')}
              </p>
            </div>
          ) : (
            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] divide-y divide-[var(--border)] overflow-hidden">
              {history.map((a, idx) => (
                <div key={a.id || idx} className="p-4 flex items-center justify-between gap-3 text-xs">
                  <div className="space-y-0.5">
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-[var(--text)]">
                        {a.itemTitle || a.concept || 'Review Attempt'}
                      </span>
                      {a.concept && (
                        <span className="text-[10px] font-semibold px-2 py-0.5 rounded-md bg-[var(--surface-raised)] text-[var(--accent)]">
                          {a.concept}
                        </span>
                      )}
                    </div>
                    {a.reviewedAt && (
                      <p className="text-[11px] text-[var(--text-secondary)]">
                        {new Date(a.reviewedAt).toLocaleString()}
                      </p>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    <span
                      className={`text-[11px] font-bold px-2.5 py-1 rounded-full ${
                        a.outcome === 'remembered'
                          ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400'
                          : 'bg-amber-500/15 text-amber-600 dark:text-amber-400'
                      }`}
                    >
                      {a.outcome === 'remembered' ? t('outcome_remembered') : t('outcome_struggled')}
                    </span>
                    <span className="text-[11px] font-semibold text-[var(--text-secondary)]">
                      Stage {a.stageBefore} → {a.stageAfter}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Create Question Modal */}
      <CreateReviewItemModal
        isOpen={isCreateModalOpen}
        onClose={() => setIsCreateModalOpen(false)}
        onCreated={handleQuestionCreated}
        initialConcept={selectedConcept}
        initialPathId={selectedPathId}
      />
    </div>
  );
}
