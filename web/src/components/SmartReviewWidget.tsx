'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { Brain, CheckCircle2, RotateCcw, Check, BookOpen, ChevronRight, Loader2 } from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import { getDueReviewsAction, submitReviewAction } from '@/app/actions/notes';
import type { NoteReview } from '@/types';

export interface SmartReviewWidgetProps {
  initialReviews?: NoteReview[];
  onReviewCompleted?: () => void;
  className?: string;
}

export function SmartReviewWidget({
  initialReviews,
  onReviewCompleted,
  className = '',
}: SmartReviewWidgetProps) {
  const { t } = usePreferences();
  const [reviews, setReviews] = useState<NoteReview[]>(initialReviews || []);
  const [loading, setLoading] = useState<boolean>(!initialReviews);
  const [submittingId, setSubmittingId] = useState<string | null>(null);

  useEffect(() => {
    if (initialReviews !== undefined) {
      return;
    }

    let active = true;
    async function loadReviews() {
      try {
        setLoading(true);
        const res = await getDueReviewsAction(20);
        if (active && res.success) {
          setReviews(res.reviews);
        }
      } catch {
        // Safe fallback on network error
      } finally {
        if (active) setLoading(false);
      }
    }

    loadReviews();
    return () => {
      active = false;
    };
  }, [initialReviews]);

  const handleReview = async (noteId: string, outcome: 'remembered' | 'struggled') => {
    if (submittingId) return;

    // Optimistic removal from queue
    const prev = [...reviews];
    setReviews((current) => current.filter((r) => r.noteId !== noteId && r.id !== noteId));
    setSubmittingId(noteId);

    try {
      const res = await submitReviewAction(noteId, outcome);
      if (!res.success) {
        // Rollback on server rejection
        setReviews(prev);
      } else {
        onReviewCompleted?.();
      }
    } catch {
      setReviews(prev);
    } finally {
      setSubmittingId(null);
    }
  };

  if (loading) {
    return (
      <div className={`p-5 rounded-2xl border border-[var(--border)] bg-[var(--surface)] ${className}`}>
        <div className="flex items-center gap-3">
          <Loader2 className="w-5 h-5 animate-spin text-[var(--accent)]" />
          <span className="text-sm text-[var(--text-secondary)]">{t('loading')}</span>
        </div>
      </div>
    );
  }

  const dueCount = reviews.length;
  const currentReview = reviews[0];

  return (
    <div
      data-testid="smart-review-widget"
      className={`p-5 rounded-2xl border border-[var(--border)] bg-[var(--surface)] shadow-sm transition-all ${className}`}
    >
      {/* Header */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-xl bg-purple-500/10 text-purple-600 dark:text-purple-400 flex items-center justify-center">
            <Brain className="w-4 h-4" />
          </div>
          <div>
            <h3 className="text-sm font-bold text-[var(--text)] flex items-center gap-2">
              {t('smart_review_title')}
              {dueCount > 0 && (
                <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-purple-500/15 text-purple-600 dark:text-purple-300">
                  {t('smart_review_due_count', { count: String(dueCount) })}
                </span>
              )}
            </h3>
            <p className="text-xs text-[var(--text-secondary)]">{t('smart_review_subtitle')}</p>
          </div>
        </div>
      </div>

      {/* Empty State */}
      {dueCount === 0 || !currentReview ? (
        <div className="flex items-center gap-3 p-3.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-800 dark:text-emerald-300">
          <CheckCircle2 className="w-5 h-5 flex-shrink-0 text-emerald-600 dark:text-emerald-400" />
          <p className="text-xs font-medium">{t('smart_review_empty')}</p>
        </div>
      ) : (
        /* Active Review Card */
        <div className="mt-2 p-4 rounded-xl border border-purple-500/20 bg-purple-500/[0.03] space-y-3">
          <div className="flex items-center justify-between text-xs">
            <span className="font-semibold uppercase tracking-wider text-[10px] px-2 py-0.5 rounded-md bg-purple-500/15 text-purple-700 dark:text-purple-300">
              {currentReview.note?.noteType === 'key_takeaway'
                ? t('note_type_takeaway')
                : currentReview.note?.noteType === 'question'
                ? t('note_type_question')
                : t('note_type_personal')}
            </span>
            <span className="text-[11px] text-[var(--text-secondary)]">
              {t('smart_review_stage', { stage: String(currentReview.stage) })} • {currentReview.intervalDays}d
            </span>
          </div>

          {currentReview.note?.book && (
            <Link
              href={`/book/${encodeURIComponent(currentReview.note.book.isbn13 || currentReview.note.bookId)}`}
              className="text-xs font-medium text-[var(--accent)] hover:underline flex items-center gap-1"
            >
              <BookOpen className="w-3.5 h-3.5" />
              <span>{currentReview.note.book.title}</span>
              <ChevronRight className="w-3 h-3" />
            </Link>
          )}

          <p className="text-sm text-[var(--text)] leading-relaxed italic font-serif">
            &ldquo;{currentReview.note?.content || 'Takeaway'}&rdquo;
          </p>

          <div className="flex items-center justify-end gap-2 pt-1 border-t border-[var(--border)]">
            <button
              type="button"
              data-testid="review-struggled-btn"
              disabled={submittingId === currentReview.noteId}
              onClick={() => handleReview(currentReview.noteId || currentReview.id, 'struggled')}
              className="px-3 py-1.5 rounded-lg border border-amber-500/30 text-amber-700 dark:text-amber-400 hover:bg-amber-500/10 text-xs font-semibold flex items-center gap-1.5 transition-colors focus:ring-2 focus:ring-amber-500/40"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              <span>{t('smart_review_struggled')}</span>
            </button>
            <button
              type="button"
              data-testid="review-remembered-btn"
              disabled={submittingId === currentReview.noteId}
              onClick={() => handleReview(currentReview.noteId || currentReview.id, 'remembered')}
              className="px-3 py-1.5 rounded-lg bg-emerald-600 text-white hover:bg-emerald-700 text-xs font-semibold flex items-center gap-1.5 shadow-sm transition-colors focus:ring-2 focus:ring-emerald-500/40"
            >
              <Check className="w-3.5 h-3.5" />
              <span>{t('smart_review_remembered')}</span>
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

