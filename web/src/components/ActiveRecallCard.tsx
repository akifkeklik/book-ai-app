'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import {
  Brain,
  CheckCircle2,
  RotateCcw,
  BookOpen,
  ChevronRight,
  Eye,
  Sparkles,
  Loader2,
  Calendar,
} from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import { submitLearningAttemptAction } from '@/app/actions/learning';
import type { ReviewItem } from '@/types';

export interface ActiveRecallCardProps {
  item: ReviewItem;
  onAttemptSubmitted?: (newStage: number, intervalDays: number, nextReviewAt: string) => void;
  className?: string;
}

export function ActiveRecallCard({
  item,
  onAttemptSubmitted,
  className = '',
}: ActiveRecallCardProps) {
  const { t } = usePreferences();
  const [revealed, setRevealed] = useState<boolean>(false);
  const [userResponse, setUserResponse] = useState<string>('');
  const [submitting, setSubmitting] = useState<boolean>(false);
  const [lastFeedback, setLastFeedback] = useState<{
    outcome: 'remembered' | 'struggled';
    intervalDays: number;
    nextReviewAt: string;
    newStage: number;
  } | null>(null);

  const handleSubmit = async (outcome: 'remembered' | 'struggled') => {
    if (submitting) return;
    setSubmitting(true);

    try {
      const res = await submitLearningAttemptAction({
        itemId: item.id,
        outcome,
        responseText: userResponse,
      });

      if (res.success && res.result) {
        setLastFeedback({
          outcome,
          intervalDays: res.result.intervalDays,
          nextReviewAt: res.result.nextReviewAt,
          newStage: res.result.newStage,
        });
        onAttemptSubmitted?.(
          res.result.newStage,
          res.result.intervalDays,
          res.result.nextReviewAt
        );
      }
    } catch {
      // Handled gracefully
    } finally {
      setSubmitting(false);
    }
  };

  const getReasonBadge = () => {
    if (item.recommendationReasonKey === 'review_overdue') {
      return (
        <span className="text-[10px] font-semibold px-2.5 py-0.5 rounded-full bg-rose-500/15 text-rose-600 dark:text-rose-400">
          {t('review_overdue_reason')}
        </span>
      );
    }
    if (item.recommendationReasonKey === 'previous_incorrect') {
      return (
        <span className="text-[10px] font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/15 text-amber-600 dark:text-amber-400">
          {t('previous_incorrect_reason')}
        </span>
      );
    }
    if (item.recommendationReasonKey === 'learning_path_continuity') {
      return (
        <span className="text-[10px] font-semibold px-2.5 py-0.5 rounded-full bg-blue-500/15 text-blue-600 dark:text-blue-400">
          {t('learning_path_continuity_reason')}
        </span>
      );
    }
    if (item.recommendationReasonKey === 'reinforcement_due') {
      return (
        <span className="text-[10px] font-semibold px-2.5 py-0.5 rounded-full bg-purple-500/15 text-purple-600 dark:text-purple-400">
          {t('reinforcement_due_reason')}
        </span>
      );
    }
    return (
      <span className="text-[10px] font-semibold px-2.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-600 dark:text-emerald-400">
        {t('concept_practice_reason')}
      </span>
    );
  };

  return (
    <div
      data-testid={`active-recall-card-${item.id}`}
      className={`p-6 rounded-2xl border border-[var(--border)] bg-[var(--surface)] shadow-md transition-all ${className}`}
    >
      {/* Top Metadata */}
      <div className="flex flex-wrap items-center justify-between gap-2 mb-4">
        <div className="flex items-center gap-2">
          <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-1 rounded-lg bg-[var(--surface-raised)] text-[var(--accent)] border border-[var(--border)]">
            {item.concept}
          </span>
          <span className="text-[11px] text-[var(--text-secondary)]">
            {t('stage_label', { stage: String(item.stage) })} • {item.intervalDays}d
          </span>
        </div>
        {getReasonBadge()}
      </div>

      {/* Book Reference if Present */}
      {item.book && (
        <div className="mb-4 p-2.5 rounded-xl bg-[var(--surface-raised)] border border-[var(--border)] flex items-center justify-between text-xs">
          <Link
            href={`/book/${encodeURIComponent(item.book.isbn13 || item.bookId || '')}`}
            className="flex items-center gap-2 text-[var(--accent)] hover:underline font-medium"
          >
            <BookOpen className="w-4 h-4 flex-shrink-0" />
            <span className="line-clamp-1">{item.book.title}</span>
            <ChevronRight className="w-3.5 h-3.5 flex-shrink-0" />
          </Link>
          {item.book.authors && (
            <span className="text-[11px] text-[var(--text-secondary)] line-clamp-1">
              {item.book.authors}
            </span>
          )}
        </div>
      )}

      {/* Question Prompt */}
      <div className="mb-5">
        <h4 className="text-xs font-semibold text-[var(--text-secondary)] mb-1 uppercase tracking-wider">
          {t('question_prompt_label')}
        </h4>
        <p className="text-lg font-semibold text-[var(--text)] leading-relaxed font-serif">
          {item.question}
        </p>
      </div>

      {/* Optional User Answer Draft Area (Prior to Reveal) */}
      {!revealed && !lastFeedback && (
        <div className="mb-4">
          <textarea
            value={userResponse}
            onChange={(e) => setUserResponse(e.target.value)}
            placeholder={t('your_answer_placeholder')}
            rows={3}
            className="w-full text-sm p-3 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] text-[var(--text)] placeholder-[var(--text-secondary)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)] resize-none"
          />
        </div>
      )}

      {/* Reveal Toggle */}
      {!revealed && !lastFeedback && (
        <button
          type="button"
          onClick={() => setRevealed(true)}
          className="w-full py-3 rounded-xl bg-[var(--accent)] text-white text-sm font-semibold hover:opacity-90 flex items-center justify-center gap-2 transition-all shadow-sm"
        >
          <Eye className="w-4 h-4" />
          <span>{t('reveal_answer')}</span>
        </button>
      )}

      {/* Revealed Section: Expected Answer, Explanation, Self Assessment */}
      {revealed && !lastFeedback && (
        <div className="mt-4 pt-4 border-t border-[var(--border)] space-y-4 animate-in fade-in duration-200">
          <div>
            <h5 className="text-xs font-semibold text-emerald-600 dark:text-emerald-400 mb-1 uppercase tracking-wider flex items-center gap-1.5">
              <CheckCircle2 className="w-3.5 h-3.5" />
              {t('question_answer_label')}
            </h5>
            <div className="p-3.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-sm text-[var(--text)] leading-relaxed">
              {item.answer}
            </div>
          </div>

          {item.explanation && (
            <div>
              <h5 className="text-xs font-semibold text-[var(--text-secondary)] mb-1 uppercase tracking-wider flex items-center gap-1.5">
                <Sparkles className="w-3.5 h-3.5 text-purple-500" />
                {t('source_evidence')}
              </h5>
              <p className="text-xs text-[var(--text-secondary)] italic leading-relaxed">
                {item.explanation}
              </p>
            </div>
          )}

          {/* Self Assessment Actions */}
          <div className="pt-2 flex flex-col sm:flex-row items-center gap-3">
            <button
              type="button"
              disabled={submitting}
              onClick={() => handleSubmit('remembered')}
              className="w-full sm:flex-1 py-3 px-4 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-bold flex items-center justify-center gap-2 transition-colors disabled:opacity-50"
            >
              {submitting ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <CheckCircle2 className="w-4 h-4" />
              )}
              <span>{t('outcome_remembered')}</span>
            </button>

            <button
              type="button"
              disabled={submitting}
              onClick={() => handleSubmit('struggled')}
              className="w-full sm:flex-1 py-3 px-4 rounded-xl bg-amber-600 hover:bg-amber-700 text-white text-sm font-bold flex items-center justify-center gap-2 transition-colors disabled:opacity-50"
            >
              {submitting ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <RotateCcw className="w-4 h-4" />
              )}
              <span>{t('outcome_struggled')}</span>
            </button>
          </div>
        </div>
      )}

      {/* Confirmation & Schedule Feedback Banner */}
      {lastFeedback && (
        <div className="mt-4 p-4 rounded-xl bg-purple-500/10 border border-purple-500/20 text-[var(--text)] space-y-2 animate-in fade-in">
          <div className="flex items-center gap-2 text-sm font-bold text-purple-600 dark:text-purple-400">
            <Brain className="w-4 h-4" />
            <span>
              {lastFeedback.outcome === 'remembered'
                ? t('outcome_remembered')
                : t('outcome_struggled')}
            </span>
          </div>
          <p className="text-xs text-[var(--text-secondary)] flex items-center gap-1.5">
            <Calendar className="w-3.5 h-3.5" />
            <span>
              {t('next_scheduled_review', {
                days: String(lastFeedback.intervalDays),
                date: new Date(lastFeedback.nextReviewAt).toLocaleDateString(),
              })}
            </span>
          </p>
        </div>
      )}
    </div>
  );
}

