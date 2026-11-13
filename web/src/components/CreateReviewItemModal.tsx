'use client';

import React, { useState } from 'react';
import { X, Plus, Sparkles, Loader2 } from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import { createLearningItemAction } from '@/app/actions/learning';
import type { ReviewItem } from '@/types';

export interface CreateReviewItemModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreated: (item: ReviewItem) => void;
  initialConcept?: string;
  initialBookId?: string;
  initialPathId?: string;
}

export function CreateReviewItemModal({
  isOpen,
  onClose,
  onCreated,
  initialConcept = '',
  initialBookId,
  initialPathId,
}: CreateReviewItemModalProps) {
  const { t } = usePreferences();
  const [title, setTitle] = useState('');
  const [concept, setConcept] = useState(initialConcept);
  const [question, setQuestion] = useState('');
  const [answer, setAnswer] = useState('');
  const [explanation, setExplanation] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !concept.trim() || !question.trim() || !answer.trim()) {
      setError(t('form_required_fields'));
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      const res = await createLearningItemAction({
        title: title.trim(),
        concept: concept.trim(),
        question: question.trim(),
        answer: answer.trim(),
        explanation: explanation.trim(),
        bookId: initialBookId,
        pathId: initialPathId,
        sourceType: 'user_created',
      });

      if (res.success && res.item) {
        onCreated(res.item);
        onClose();
      } else {
        setError(res.error || 'Failed to create question.');
      }
    } catch {
      setError(t('unexpected_error'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
    >
      <div className="w-full max-w-lg rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-6 shadow-2xl space-y-4">
        {/* Header */}
        <div className="flex items-center justify-between pb-3 border-b border-[var(--border)]">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-xl bg-[var(--accent)]/10 text-[var(--accent)] flex items-center justify-center">
              <Sparkles className="w-4 h-4" />
            </div>
            <h3 className="text-base font-bold text-[var(--text)]">
              {t('create_question_title')}
            </h3>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-lg text-[var(--text-secondary)] hover:bg-[var(--surface-raised)]"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {error && (
          <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 text-xs">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-3.5">
          <div>
            <label className="block text-xs font-semibold text-[var(--text)] mb-1">
              {t('question_title_label')} *
            </label>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={t('review_title_hint')}
              className="w-full text-sm p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] text-[var(--text)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-[var(--text)] mb-1">
              {t('question_concept_label')} *
            </label>
            <input
              type="text"
              required
              value={concept}
              onChange={(e) => setConcept(e.target.value)}
              placeholder={t('review_concept_hint')}
              className="w-full text-sm p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] text-[var(--text)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)]"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-[var(--text)] mb-1">
              {t('question_prompt_label')} *
            </label>
            <textarea
              required
              rows={2}
              value={question}
              onChange={(e) => setQuestion(e.target.value)}
              placeholder={t('review_prompt_hint')}
              className="w-full text-sm p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] text-[var(--text)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)] resize-none"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-[var(--text)] mb-1">
              {t('question_answer_label')} *
            </label>
            <textarea
              required
              rows={3}
              value={answer}
              onChange={(e) => setAnswer(e.target.value)}
              placeholder={t('review_answer_hint')}
              className="w-full text-sm p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] text-[var(--text)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)] resize-none"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-[var(--text)] mb-1">
              {t('question_explanation_label')}
            </label>
            <textarea
              rows={2}
              value={explanation}
              onChange={(e) => setExplanation(e.target.value)}
              placeholder={t('review_context_hint')}
              className="w-full text-sm p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] text-[var(--text)] focus:outline-none focus:ring-2 focus:ring-[var(--accent)] resize-none"
            />
          </div>

          <div className="pt-2 flex items-center justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl border border-[var(--border)] text-xs font-semibold text-[var(--text-secondary)] hover:bg-[var(--surface-raised)]"
            >
              {t('cancel')}
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="px-5 py-2 rounded-xl bg-[var(--accent)] text-white text-xs font-bold hover:opacity-90 flex items-center gap-1.5 disabled:opacity-50"
            >
              {submitting ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Plus className="w-3.5 h-3.5" />
              )}
              <span>{t('save_question_button')}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

