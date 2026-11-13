'use client';

import Link from 'next/link';
import { Brain, X } from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import type { RecallItemPreview } from '@/types';

/** Human-friendly "tomorrow" / "in 3 days" in the user's language. */
export function formatRelativeReview(nextReviewAt: string | null | undefined, lang: string, now: Date = new Date()): string {
  if (!nextReviewAt) return '';
  const due = new Date(nextReviewAt);
  if (Number.isNaN(due.getTime())) return '';
  const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.max(0, Math.round((startOfDay(due) - startOfDay(now)) / 86_400_000));
  return new Intl.RelativeTimeFormat(lang, { numeric: 'auto' }).format(days, 'day');
}

interface RecallPreviewCardProps {
  item: RecallItemPreview;
  onDismiss: () => void;
}

/**
 * Shown right after a key takeaway is saved: the AI-generated recall question and when
 * Libris will ask it. This is the moment the product's value becomes visible.
 */
export function RecallPreviewCard({ item, onDismiss }: RecallPreviewCardProps) {
  const { t, preferences } = usePreferences();
  const when = formatRelativeReview(item.nextReviewAt, preferences.language);

  return (
    <div
      role="status"
      aria-live="polite"
      data-testid="recall-preview-card"
      className="animate-fade-in"
      style={{
        display: 'flex',
        gap: '0.85rem',
        alignItems: 'flex-start',
        padding: '1rem 1.1rem',
        marginBottom: '1.25rem',
        borderRadius: '14px',
        border: '1px solid var(--primary)',
        background: 'color-mix(in srgb, var(--primary) 10%, transparent)',
      }}
    >
      <Brain size={22} aria-hidden="true" style={{ color: 'var(--primary)', flexShrink: 0, marginTop: '0.15rem' }} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={{ margin: 0, fontSize: '0.8rem', fontWeight: 700, color: 'var(--primary)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
          {t('recall_card_title')}
        </p>
        <p style={{ margin: '0.35rem 0', fontSize: '1.02rem', fontWeight: 600, color: 'var(--text-primary)', overflowWrap: 'anywhere' }}>
          {item.question}
        </p>
        <p style={{ margin: 0, fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
          {when ? t('recall_card_next', { when }) : null}{' '}
          <Link href="/learning" style={{ color: 'var(--primary)', fontWeight: 600 }}>
            {t('recall_card_open')}
          </Link>
        </p>
      </div>
      <button
        type="button"
        onClick={onDismiss}
        aria-label={t('recall_card_dismiss')}
        title={t('recall_card_dismiss')}
        style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: '0.15rem' }}
      >
        <X size={18} aria-hidden="true" />
      </button>
    </div>
  );
}
