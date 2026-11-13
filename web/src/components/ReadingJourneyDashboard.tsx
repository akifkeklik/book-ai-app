'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import type { Book, LibraryCollectionStatus, LibraryItem } from '@/types';
import {
  calculateReadingJourney,
  loadSavedReadingGoal,
  saveReadingGoal,
  type ReadingGoal,
  type ReadingGoalType,
} from '@/lib/reading_journey';
import { usePreferences } from '@/components/PreferencesProvider';
import { localizeRecommendationReason } from '@/lib/i18n';
import { SmartReviewWidget } from './SmartReviewWidget';
import { NotesExportModal } from './NotesExportModal';
import { LearningPathsDashboard } from './LearningPathsDashboard';
import {
  BookOpen,
  Trophy,
  Target,
  CheckCircle2,
  BookMarked,
  Sparkles,
  Play,
  RotateCcw,
  Trash2,
  Bookmark,
  Info,
  Download,
} from 'lucide-react';
import { BookCoverFallback } from './BookCoverFallback';

export interface ReadingJourneyDashboardProps {
  items: LibraryItem[];
  nextBook?: Book | null;
  onUpdateStatus?: (bookId: string, status: LibraryCollectionStatus | 'clear') => void;
  isUpdating?: boolean;
}

export function ReadingJourneyDashboard({
  items,
  nextBook,
  onUpdateStatus,
  isUpdating = false,
}: ReadingJourneyDashboardProps) {
  const { t } = usePreferences();

  // Goal persisted locally on device per specifications
  const [goal, setGoal] = useState<ReadingGoal>(() => loadSavedReadingGoal());
  const [isEditingGoal, setIsEditingGoal] = useState(false);
  const [goalTypeInput, setGoalTypeInput] = useState<ReadingGoalType>(() => goal.type);
  const [goalTargetInput, setGoalTargetInput] = useState<string>(() => String(goal.target));
  const [goalCategoryInput, setGoalCategoryInput] = useState<string>(() => goal.category || '');

  // Active tab inside Reading Journey: 'reading' | 'want_to_read' | 'finished'
  const [activeShelfTab, setActiveShelfTab] = useState<'reading' | 'want_to_read' | 'finished'>('reading');
  const [isExportModalOpen, setIsExportModalOpen] = useState(false);

  const handleSaveGoal = (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = parseInt(goalTargetInput, 10);
    const safeTarget = !isNaN(parsed) && parsed > 0 && parsed <= 500 ? parsed : (goalTypeInput === 'weekly' ? 1 : 20);

    const nextGoal: ReadingGoal = {
      type: goalTypeInput,
      target: safeTarget,
      category: goalTypeInput === 'category' && goalCategoryInput.trim() ? goalCategoryInput.trim() : undefined,
    };

    setGoal(nextGoal);
    saveReadingGoal(nextGoal);
    setIsEditingGoal(false);
  };

  const journey = calculateReadingJourney(items, goal);
  const {
    safeGoal,
    completedCount,
    readingCount,
    wantToReadCount,
    progressPercent,
    isGoalReached,
    readingBooks,
    wantToReadBooks,
    completedBooks,
  } = journey;

  const currentYear = new Date().getFullYear();
  const currentWeek = Math.ceil(
    ((Date.now() - new Date(currentYear, 0, 1).getTime()) / 86400000 + new Date(currentYear, 0, 1).getDay() + 1) / 7
  );

  const goalLabel =
    goal.type === 'weekly'
      ? `${goal.target} book${goal.target > 1 ? 's' : ''}/week`
      : goal.type === 'category' && goal.category
      ? `${goal.target} ${goal.category} books`
      : `${goal.target} books/year`;

  const localizedNextReason = nextBook
    ? nextBook.recommendationReason
      ? localizeRecommendationReason(nextBook.recommendationReason, t)
      : nextBook.explanation || null
    : null;

  return (
    <section
      aria-label={t('rj_label')}
      className="glass-panel reading-journey-dashboard animate-fade-in"
      style={{
        borderRadius: '20px',
        padding: '1.75rem',
        marginBottom: '2.5rem',
        background: 'linear-gradient(135deg, var(--surface) 0%, var(--surface-subtle) 100%)',
        border: '1px solid var(--card-border)',
      }}
    >
      {/* ── Top Header Row ──────────────────────────────────────────────── */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexWrap: 'wrap',
          gap: '1rem',
          marginBottom: '1.5rem',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
          <div
            style={{
              width: '44px',
              height: '44px',
              borderRadius: '12px',
              background: 'linear-gradient(135deg, var(--primary), var(--accent))',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#ffffff',
              boxShadow: '0 4px 12px rgba(99, 102, 241, 0.25)',
            }}
          >
            <Trophy size={22} />
          </div>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <h2 style={{ fontSize: '1.35rem', fontWeight: 700, margin: 0 }}>
                {goal.type === 'weekly' ? `Week ${currentWeek}` : currentYear} Reading Journey
              </h2>
              <span
                style={{
                  fontSize: '0.7rem',
                  fontWeight: 600,
                  padding: '2px 8px',
                  borderRadius: '9999px',
                  background: 'rgba(99, 102, 241, 0.12)',
                  color: 'var(--primary)',
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: '4px',
                }}
                title={t('rj_local_goal_title')}
              >
                <Info size={11} />
                <span>{t('rj_local_goal')}</span>
              </span>
            </div>
            <p className="text-muted" style={{ fontSize: '0.85rem', margin: '2px 0 0' }}>
              {t('rj_subtitle')}
            </p>
          </div>
        </div>

        {/* Action Buttons */}
        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
          <button
            type="button"
            onClick={() => setIsExportModalOpen(true)}
            className="btn btn-outline"
            style={{ padding: '0.4rem 0.85rem', fontSize: '0.8rem', gap: '0.45rem' }}
            title={t('export_notes')}
            aria-label={t('export_notes')}
          >
            <Download size={14} color="var(--primary)" />
            <span>{t('export_notes')}</span>
          </button>

          {isEditingGoal ? (
            <form
              onSubmit={handleSaveGoal}
              style={{
                display: 'flex',
                gap: '0.5rem',
                alignItems: 'center',
                flexWrap: 'wrap',
                background: 'var(--surface-elevated)',
                padding: '0.5rem 0.75rem',
                borderRadius: '10px',
                border: '1px solid var(--primary)',
              }}
            >
              <select
                value={goalTypeInput}
                onChange={(e) => setGoalTypeInput(e.target.value as ReadingGoalType)}
                style={{
                  padding: '0.35rem 0.5rem',
                  borderRadius: '6px',
                  background: 'var(--surface-subtle)',
                  border: '1px solid var(--card-border)',
                  color: 'var(--foreground)',
                  fontSize: '0.8rem',
                }}
              >
                <option value="annual">{t('rj_goal_annual')}</option>
                <option value="weekly">{t('rj_goal_weekly')}</option>
                <option value="category">{t('rj_goal_topic')}</option>
              </select>

              <input
                type="number"
                min="1"
                max="500"
                value={goalTargetInput}
                onChange={(e) => setGoalTargetInput(e.target.value)}
                style={{
                  width: '65px',
                  padding: '0.35rem 0.5rem',
                  borderRadius: '6px',
                  background: 'var(--surface-subtle)',
                  border: '1px solid var(--card-border)',
                  color: 'var(--foreground)',
                  fontSize: '0.8rem',
                }}
                autoFocus
              />

              {goalTypeInput === 'category' && (
                <input
                  type="text"
                  placeholder={t('rj_topic_hint')}
                  value={goalCategoryInput}
                  onChange={(e) => setGoalCategoryInput(e.target.value)}
                  style={{
                    width: '120px',
                    padding: '0.35rem 0.5rem',
                    borderRadius: '6px',
                    background: 'var(--surface-subtle)',
                    border: '1px solid var(--card-border)',
                    color: 'var(--foreground)',
                    fontSize: '0.8rem',
                  }}
                />
              )}

              <button
                type="submit"
                className="btn btn-primary"
                style={{ padding: '0.35rem 0.75rem', fontSize: '0.8rem' }}
              >
                {t('save')}
              </button>
              <button
                type="button"
                onClick={() => setIsEditingGoal(false)}
                className="btn btn-outline"
                style={{ padding: '0.35rem 0.6rem', fontSize: '0.8rem' }}
              >
                {t('cancel')}
              </button>
            </form>
          ) : (
            <button
              type="button"
              onClick={() => {
                setGoalTypeInput(goal.type);
                setGoalTargetInput(String(goal.target));
                setGoalCategoryInput(goal.category || '');
                setIsEditingGoal(true);
              }}
              className="btn btn-outline"
              style={{ padding: '0.4rem 0.85rem', fontSize: '0.8rem', gap: '0.45rem' }}
              title={t('rj_change_goal_label')}
            >
              <Target size={14} color="var(--primary)" />
              <span>Goal: {goalLabel}</span>
            </button>
          )}
        </div>
      </div>

      {/* ── SaaS Metric Cards Strip ────────────────────────────────────── */}
      <div className="saas-metric-grid" style={{ marginBottom: '1.5rem' }}>
        {/* Metric 1: Reading Goal Pace */}
        <div className="saas-metric-card">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('rj_goal_pace')}</span>
            <div className="saas-metric-icon">
              <Target size={16} />
            </div>
          </div>
          <div className="saas-metric-value">
            {progressPercent}%
          </div>
          <div className="saas-metric-footer">
            <span className={`saas-pulse-dot ${isGoalReached ? 'emerald' : 'blue'}`} />
            <span>{completedCount} of {safeGoal} Books {isGoalReached ? '(Completed)' : 'Target'}</span>
          </div>
        </div>

        {/* Metric 2: Currently Reading */}
        <div className="saas-metric-card">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('rj_active')}</span>
            <div className="saas-metric-icon" style={{ background: 'rgba(245, 158, 11, 0.12)', color: '#f59e0b', borderColor: 'rgba(245, 158, 11, 0.28)' }}>
              <BookOpen size={16} />
            </div>
          </div>
          <div className="saas-metric-value">
            {readingCount}
          </div>
          <div className="saas-metric-footer">
            <span className="saas-pulse-dot amber" />
            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: '180px' }}>
              {readingBooks.length > 0 ? (readingBooks[0].book?.title || 'Active read') : 'Shelf ready for next read'}
            </span>
          </div>
        </div>

        {/* Metric 3: Reading Queue */}
        <div className="saas-metric-card">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('status_want_to_read')}</span>
            <div className="saas-metric-icon" style={{ background: 'rgba(56, 189, 248, 0.12)', color: '#38bdf8', borderColor: 'rgba(56, 189, 248, 0.28)' }}>
              <Bookmark size={16} />
            </div>
          </div>
          <div className="saas-metric-value">
            {wantToReadCount}
          </div>
          <div className="saas-metric-footer">
            <span className="saas-pulse-dot blue" />
            <span>{t('rj_want_desc')}</span>
          </div>
        </div>

        {/* Metric 4: Completed Milestones */}
        <div className="saas-metric-card">
          <div className="saas-metric-header">
            <span className="saas-metric-label">{t('rj_finished')}</span>
            <div className="saas-metric-icon" style={{ background: 'rgba(16, 185, 129, 0.12)', color: '#10b981', borderColor: 'rgba(16, 185, 129, 0.28)' }}>
              <CheckCircle2 size={16} />
            </div>
          </div>
          <div className="saas-metric-value">
            {completedCount}
          </div>
          <div className="saas-metric-footer">
            <span className="saas-pulse-dot emerald" />
            <span>{completedBooks.reduce((acc, b) => acc + (b.book?.pageCount || 0), 0).toLocaleString()} pages logged</span>
          </div>
        </div>
      </div>

      {/* ── Goal Progress Bar & Metrics ─────────────────────────────────── */}
      <div
        style={{
          background: 'var(--surface-elevated)',
          padding: '1.25rem',
          borderRadius: '16px',
          marginBottom: '1.75rem',
          border: '1px solid var(--card-border)',
          boxShadow: 'var(--saas-card-shadow)',
        }}
      >
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            marginBottom: '0.75rem',
            flexWrap: 'wrap',
            gap: '0.5rem',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', flexWrap: 'wrap' }}>
            <span style={{ fontSize: '0.95rem', fontWeight: 600 }}>
              Progress:{' '}
              <strong style={{ color: 'var(--foreground)' }}>{completedCount}</strong> of{' '}
              <strong style={{ color: 'var(--primary)' }}>{safeGoal}</strong> {goal.type === 'category' && goal.category ? `${goal.category} ` : ''}books
            </span>
            {isGoalReached && (
              <span
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: '4px',
                  background: 'rgba(16, 185, 129, 0.15)',
                  color: 'var(--success, #10b981)',
                  fontSize: '0.75rem',
                  fontWeight: 700,
                  padding: '2px 8px',
                  borderRadius: '9999px',
                }}
              >
                <CheckCircle2 size={12} /> Goal Achieved!
              </span>
            )}
          </div>
          <span style={{ fontWeight: 700, fontSize: '1rem', color: 'var(--primary)' }}>
            {progressPercent}%
          </span>
        </div>

        {/* Accessible Progress Bar */}
        <div
          role="progressbar"
          aria-valuenow={progressPercent}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-label={`Reading progress: ${completedCount} of ${safeGoal} books (${progressPercent}%)`}
          style={{
            height: '10px',
            borderRadius: '9999px',
            background: 'rgba(255, 255, 255, 0.08)',
            overflow: 'hidden',
            position: 'relative',
          }}
        >
          <div
            style={{
              height: '100%',
              width: `${progressPercent}%`,
              background: isGoalReached
                ? 'linear-gradient(90deg, #10b981, #059669)'
                : 'linear-gradient(90deg, var(--primary), var(--accent))',
              borderRadius: '9999px',
              transition: 'width 0.4s ease',
            }}
          />
        </div>

        {/* Milestone Sub-counters */}
        <div
          style={{
            display: 'flex',
            gap: '1.5rem',
            marginTop: '0.85rem',
            fontSize: '0.8rem',
            color: 'var(--text-muted)',
            flexWrap: 'wrap',
          }}
        >
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <span className="saas-pulse-dot emerald" style={{ width: '8px', height: '8px' }} />
            Completed: <strong>{completedCount}</strong>
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <span className="saas-pulse-dot amber" style={{ width: '8px', height: '8px' }} />
            Currently Reading: <strong>{readingCount}</strong>
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <span className="saas-pulse-dot blue" style={{ width: '8px', height: '8px' }} />
            Reading List: <strong>{wantToReadCount}</strong>
          </span>
        </div>

        {/* Weekly Reading Activity Visualizer */}
        <div style={{ marginTop: '1.25rem', paddingTop: '1.25rem', borderTop: '1px solid var(--card-border)' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.65rem' }}>
            <span style={{ fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)' }}>
              {t('rj_activity_title')}
            </span>
            <span style={{ fontSize: '0.75rem', color: 'var(--electric-blue)', fontWeight: 600 }}>
              {t('rj_habit_active')}
            </span>
          </div>
          <div className="saas-activity-chart" role="img" aria-label={t('rj_activity_label')}>
            {[
              { day: 'Mon', height: '55%', active: false },
              { day: 'Tue', height: '80%', active: false },
              { day: 'Wed', height: '40%', active: false },
              { day: 'Thu', height: '90%', active: false },
              { day: 'Fri', height: '65%', active: false },
              { day: 'Sat', height: '100%', active: true },
              { day: 'Sun', height: '75%', active: true },
            ].map((d) => (
              <div key={d.day} className="saas-chart-col">
                <div className="saas-chart-bar-wrap" title={`${d.day}: ${d.height} activity pace`}>
                  <div
                    className="saas-chart-bar-fill"
                    style={{
                      height: d.height,
                      background: d.active
                        ? 'linear-gradient(180deg, #38bdf8 0%, #0284c7 100%)'
                        : 'linear-gradient(180deg, rgba(56, 189, 248, 0.7) 0%, rgba(14, 165, 233, 0.3) 100%)',
                    }}
                  />
                </div>
                <span className="saas-chart-day-label">{d.day}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ── Next Book Spotlight (Sonraki Kitap) ─────────────────────────── */}
      {nextBook && onUpdateStatus && (
        <div
          className="next-book-spotlight"
          style={{
            background: 'linear-gradient(135deg, rgba(99, 102, 241, 0.08) 0%, rgba(139, 92, 246, 0.12) 100%)',
            border: '1px solid rgba(139, 92, 246, 0.3)',
            borderRadius: '16px',
            padding: '1.25rem',
            marginBottom: '1.75rem',
            display: 'flex',
            gap: '1.25rem',
            alignItems: 'center',
            flexWrap: 'wrap',
          }}
        >
          {/* Cover */}
          <div
            style={{
              width: '60px',
              height: '90px',
              borderRadius: '8px',
              overflow: 'hidden',
              flexShrink: 0,
              position: 'relative',
              boxShadow: '0 4px 10px rgba(0, 0, 0, 0.2)',
            }}
          >
            {nextBook.thumbnail && nextBook.thumbnail !== 'None' ? (
              /* eslint-disable-next-line @next/next/no-img-element */
              <img
                src={nextBook.thumbnail.replace('http:', 'https:')}
                alt={nextBook.title}
                style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                loading="lazy"
              />
            ) : (
              <BookCoverFallback
                title={nextBook.title}
                authors={nextBook.authors}
                style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%' }}
              />
            )}
          </div>

          {/* Details */}
          <div style={{ flex: 1, minWidth: '220px' }}>
            <div
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '4px',
                padding: '2px 8px',
                borderRadius: '6px',
                background: 'rgba(139, 92, 246, 0.18)',
                color: 'var(--accent)',
                fontSize: '0.72rem',
                fontWeight: 700,
                textTransform: 'uppercase',
                letterSpacing: '0.04em',
                marginBottom: '0.4rem',
              }}
            >
              <Sparkles size={11} />
              <span>{t('rj_next_read')}</span>
            </div>

            <Link
              href={`/book/${nextBook.isbn13}`}
              style={{ textDecoration: 'none', color: 'inherit' }}
            >
              <h3 style={{ fontSize: '1.05rem', fontWeight: 700, margin: '0 0 2px' }}>
                {nextBook.title}
              </h3>
            </Link>
            <p className="text-muted" style={{ fontSize: '0.82rem', margin: '0 0 6px' }}>
              {nextBook.authors || 'Unknown Author'}
            </p>

            {/* Real Backend Explanation */}
            {localizedNextReason && (
              <p
                style={{
                  fontSize: '0.78rem',
                  color: 'var(--accent)',
                  margin: 0,
                  fontStyle: 'italic',
                }}
              >
                &ldquo;{localizedNextReason}&rdquo;
              </p>
            )}
          </div>

          {/* One-touch Actions */}
          <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
            <button
              type="button"
              onClick={() => onUpdateStatus(nextBook.isbn13, 'reading')}
              disabled={isUpdating}
              className="btn btn-primary"
              style={{ padding: '0.45rem 0.9rem', fontSize: '0.8rem', gap: '0.4rem' }}
              title={t('rj_start_label')}
            >
              <Play size={14} fill="currentColor" />
              <span>{t('start_reading')}</span>
            </button>

            <button
              type="button"
              onClick={() => onUpdateStatus(nextBook.isbn13, 'want_to_read')}
              disabled={isUpdating}
              className="btn btn-outline"
              style={{ padding: '0.45rem 0.8rem', fontSize: '0.8rem', gap: '0.4rem' }}
              title={t('rj_save_label')}
            >
              <Bookmark size={14} />
              <span>{t('rj_save_later')}</span>
            </button>
          </div>
        </div>
      )}

      {/* ── Smart Review & Recall Center ─────────────────────────────── */}
      <div style={{ marginBottom: '1.75rem' }}>
        <SmartReviewWidget />
      </div>

      {/* ── Personalized Learning Paths ───────────────────────────────── */}
      <div style={{ marginBottom: '1.75rem' }}>
        <LearningPathsDashboard />
      </div>

      {/* ── Reading Journey Shelves (Tabs & Content) ─────────────────────── */}
      <div>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            marginBottom: '1rem',
            flexWrap: 'wrap',
            gap: '0.75rem',
          }}
        >
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <button
              type="button"
              onClick={() => setActiveShelfTab('reading')}
              style={{
                padding: '0.35rem 0.85rem',
                borderRadius: '8px',
                fontSize: '0.8rem',
                fontWeight: 600,
                border: '1px solid var(--card-border)',
                background: activeShelfTab === 'reading' ? 'var(--primary)' : 'rgba(255, 255, 255, 0.04)',
                color: activeShelfTab === 'reading' ? '#ffffff' : 'var(--foreground)',
                cursor: 'pointer',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.35rem',
              }}
            >
              <BookOpen size={14} />
              <span>Currently Reading ({readingBooks.length})</span>
            </button>

            <button
              type="button"
              onClick={() => setActiveShelfTab('want_to_read')}
              style={{
                padding: '0.35rem 0.85rem',
                borderRadius: '8px',
                fontSize: '0.8rem',
                fontWeight: 600,
                border: '1px solid var(--card-border)',
                background: activeShelfTab === 'want_to_read' ? 'var(--primary)' : 'rgba(255, 255, 255, 0.04)',
                color: activeShelfTab === 'want_to_read' ? '#ffffff' : 'var(--foreground)',
                cursor: 'pointer',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.35rem',
              }}
            >
              <Bookmark size={14} />
              <span>Want to Read ({wantToReadBooks.length})</span>
            </button>

            <button
              type="button"
              onClick={() => setActiveShelfTab('finished')}
              style={{
                padding: '0.35rem 0.85rem',
                borderRadius: '8px',
                fontSize: '0.8rem',
                fontWeight: 600,
                border: '1px solid var(--card-border)',
                background: activeShelfTab === 'finished' ? 'var(--primary)' : 'rgba(255, 255, 255, 0.04)',
                color: activeShelfTab === 'finished' ? '#ffffff' : 'var(--foreground)',
                cursor: 'pointer',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.35rem',
              }}
            >
              <CheckCircle2 size={14} />
              <span>Completed ({completedBooks.length})</span>
            </button>
          </div>
        </div>

        {/* Shelf Content */}
        {(() => {
          const currentList =
            activeShelfTab === 'reading'
              ? readingBooks
              : activeShelfTab === 'want_to_read'
              ? wantToReadBooks
              : completedBooks;

          if (currentList.length === 0) {
            return (
              <div
                style={{
                  padding: '1.75rem',
                  borderRadius: '12px',
                  background: 'rgba(255, 255, 255, 0.02)',
                  border: '1px dashed var(--card-border)',
                  textAlign: 'center',
                  color: 'var(--text-muted)',
                  fontSize: '0.9rem',
                }}
              >
                {activeShelfTab === 'reading' && (
                  <>
                    No books currently marked as &ldquo;Reading&rdquo;.
                    {wantToReadBooks.length > 0 ? (
                      <span style={{ display: 'block', marginTop: '0.25rem' }}>
                        You have {wantToReadBooks.length} title{wantToReadBooks.length > 1 ? 's' : ''} in your Want to Read shelf waiting to be started!
                      </span>
                    ) : (
                      <span style={{ display: 'block', marginTop: '0.25rem' }}>
                        Pick a book from the recommendations below and tap &ldquo;Start Reading&rdquo;.
                      </span>
                    )}
                  </>
                )}
                {activeShelfTab === 'want_to_read' && (
                  <>
                    {t('rj_want_empty')}
                    <span style={{ display: 'block', marginTop: '0.25rem' }}>
                      {t('rj_want_empty_desc')}
                    </span>
                  </>
                )}
                {activeShelfTab === 'finished' && (
                  <>
                    {t('rj_finished_empty')}
                    <span style={{ display: 'block', marginTop: '0.25rem' }}>
                      {t('rj_finished_empty_desc')}
                    </span>
                  </>
                )}
              </div>
            );
          }

          return (
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))',
                gap: '1rem',
              }}
            >
              {currentList.map((item) => {
                const book = item.book;
                const hasPageCount = typeof book.pageCount === 'number' && book.pageCount > 0;

                return (
                  <div
                    key={item.id || item.bookId}
                    style={{
                      display: 'flex',
                      flexDirection: 'column',
                      padding: '0.85rem',
                      borderRadius: '12px',
                      background: 'var(--surface-elevated)',
                      border: '1px solid var(--card-border)',
                      gap: '0.75rem',
                    }}
                  >
                    <div style={{ display: 'flex', gap: '0.85rem', alignItems: 'center' }}>
                      {/* Thumbnail */}
                      <Link
                        href={`/book/${item.bookId}`}
                        style={{
                          width: '44px',
                          height: '64px',
                          borderRadius: '6px',
                          overflow: 'hidden',
                          flexShrink: 0,
                          position: 'relative',
                          background: 'var(--surface)',
                          display: 'block',
                        }}
                      >
                        {book.thumbnail && book.thumbnail !== 'None' ? (
                          /* eslint-disable-next-line @next/next/no-img-element */
                          <img
                            src={book.thumbnail.replace('http:', 'https:')}
                            alt={book.title}
                            style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                            loading="lazy"
                          />
                        ) : (
                          <BookCoverFallback
                            title={book.title}
                            authors={book.authors}
                            style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%' }}
                          />
                        )}
                      </Link>

                      {/* Title & Metadata */}
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <Link
                          href={`/book/${item.bookId}`}
                          style={{ textDecoration: 'none', color: 'inherit' }}
                        >
                          <h4
                            style={{
                              fontSize: '0.9rem',
                              fontWeight: 600,
                              margin: 0,
                              overflow: 'hidden',
                              textOverflow: 'ellipsis',
                              whiteSpace: 'nowrap',
                            }}
                          >
                            {book.title}
                          </h4>
                        </Link>
                        <p
                          className="text-muted"
                          style={{
                            fontSize: '0.78rem',
                            margin: '2px 0 4px',
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                            whiteSpace: 'nowrap',
                          }}
                        >
                          {book.authors || 'Unknown Author'}
                        </p>
                        <div
                          style={{
                            display: 'flex',
                            alignItems: 'center',
                            gap: '6px',
                            fontSize: '0.75rem',
                            color: 'var(--text-muted)',
                          }}
                        >
                          <BookMarked size={12} color="var(--reading, #f59e0b)" />
                          <span>{hasPageCount ? `${book.pageCount} pages` : 'In progress'}</span>
                        </div>
                      </div>
                    </div>

                    {/* One-touch Actions Row */}
                    {onUpdateStatus && (
                      <div
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'space-between',
                          gap: '0.4rem',
                          paddingTop: '0.5rem',
                          borderTop: '1px solid rgba(255, 255, 255, 0.05)',
                        }}
                      >
                        {activeShelfTab === 'want_to_read' && (
                          <>
                            <button
                              type="button"
                              onClick={() => onUpdateStatus(item.bookId, 'reading')}
                              disabled={isUpdating}
                              className="btn btn-outline"
                              style={{ padding: '0.25rem 0.6rem', fontSize: '0.72rem', gap: '0.25rem' }}
                            >
                              <Play size={11} fill="currentColor" />
                              <span>{t('start_reading')}</span>
                            </button>
                            <button
                              type="button"
                              onClick={() => onUpdateStatus(item.bookId, 'finished')}
                              disabled={isUpdating}
                              className="btn btn-outline"
                              style={{ padding: '0.25rem 0.6rem', fontSize: '0.72rem', gap: '0.25rem' }}
                            >
                              <CheckCircle2 size={11} />
                              <span>{t('status_finished')}</span>
                            </button>
                          </>
                        )}

                        {activeShelfTab === 'reading' && (
                          <>
                            <button
                              type="button"
                              onClick={() => onUpdateStatus(item.bookId, 'finished')}
                              disabled={isUpdating}
                              className="btn btn-outline"
                              style={{ padding: '0.25rem 0.6rem', fontSize: '0.72rem', gap: '0.25rem', color: '#10b981' }}
                            >
                              <CheckCircle2 size={11} />
                              <span>{t('mark_as_finished')}</span>
                            </button>
                            <button
                              type="button"
                              onClick={() => onUpdateStatus(item.bookId, 'want_to_read')}
                              disabled={isUpdating}
                              className="btn btn-outline"
                              style={{ padding: '0.25rem 0.6rem', fontSize: '0.72rem', gap: '0.25rem' }}
                            >
                              <Bookmark size={11} />
                              <span>{t('rj_to_list')}</span>
                            </button>
                          </>
                        )}

                        {activeShelfTab === 'finished' && (
                          <button
                            type="button"
                            onClick={() => onUpdateStatus(item.bookId, 'reading')}
                            disabled={isUpdating}
                            className="btn btn-outline"
                            style={{ padding: '0.25rem 0.6rem', fontSize: '0.72rem', gap: '0.25rem' }}
                          >
                            <RotateCcw size={11} />
                            <span>{t('rj_read_again')}</span>
                          </button>
                        )}

                        <button
                          type="button"
                          onClick={() => onUpdateStatus(item.bookId, 'clear')}
                          disabled={isUpdating}
                          className="btn btn-outline"
                          style={{
                            padding: '0.25rem 0.5rem',
                            fontSize: '0.72rem',
                            marginLeft: 'auto',
                            color: 'var(--muted)',
                          }}
                          title={t('rj_remove_label')}
                          aria-label={`Remove ${book.title} from shelf`}
                        >
                          <Trash2 size={12} />
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          );
        })()}
      </div>

      {/* ── Notes Export Modal ────────────────────────────────────────── */}
      <NotesExportModal
        isOpen={isExportModalOpen}
        onClose={() => setIsExportModalOpen(false)}
      />
    </section>
  );
}
