'use client';

import { useState, useEffect, useRef } from 'react';
import Link from 'next/link';
import { submitFeedbackAction, trackActivityAction } from '@/app/actions/user';
import {
  removeLibraryItem,
  addFavoriteItem,
  removeFavoriteItem,
} from '@/app/actions/library';
import { ThumbsUp, ThumbsDown, Heart, Bookmark, Check, AlertCircle, Trash2, BookOpen, CheckCircle2, WifiOff } from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';

interface BookFeedbackProps {
  bookId: string;
  initialInteraction?: string | null;
  initialIsFavorite?: boolean;
  interactionError?: string | null;
  isAuthenticated?: boolean;
}

export default function BookFeedback({
  bookId,
  initialInteraction = null,
  initialIsFavorite = false,
  interactionError = null,
  isAuthenticated = false,
}: BookFeedbackProps) {
  const { t } = usePreferences();
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error' | 'offline_pending'>(
    interactionError ? 'error' : 'idle'
  );

  // Independent favorite status (Model A canonical)
  const [isFavorite, setIsFavorite] = useState<boolean>(
    initialIsFavorite || initialInteraction === 'favorite'
  );

  // Separate reading status / recommendation signal (like, dislike, want_to_read, reading, finished)
  const [activeFeedback, setActiveFeedback] = useState<string | null>(
    initialInteraction === 'favorite' ? null : initialInteraction || null
  );

  const [feedbackSuccessText, setFeedbackSuccessText] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(interactionError || null);
  const [isOffline, setIsOffline] = useState<boolean>(
    typeof navigator !== 'undefined' ? !navigator.onLine : false
  );
  const hasTracked = useRef(false);

  useEffect(() => {
    const handleOnline = () => setIsOffline(false);
    const handleOffline = () => setIsOffline(true);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  useEffect(() => {
    // Only track authenticated visits to prevent unnecessary 401 calls
    if (isAuthenticated && !hasTracked.current) {
      hasTracked.current = true;
      trackActivityAction(bookId, 'view').catch(() => {});
    }
  }, [bookId, isAuthenticated]);

  const handleFavoriteToggle = async () => {
    const currentlyFav = isFavorite;
    const targetAction = currentlyFav ? 'remove' : 'add';

    // Optimistic favorite update - does NOT mutate active reading status or signals!
    setIsFavorite(!currentlyFav);
    setStatus('loading');
    setErrorMessage(null);
    setFeedbackSuccessText(null);

    try {
      const res = currentlyFav
        ? await removeFavoriteItem(bookId)
        : await addFavoriteItem(bookId);

      if (res.success) {
        setStatus('success');
        setFeedbackSuccessText(
          currentlyFav ? 'Removed from favorites.' : 'Added to favorites! Recommendations updated.'
        );
      } else {
        // Rollback on failure
        setIsFavorite(currentlyFav);
        setStatus('error');
        setErrorMessage(
          res.error === 'Unauthorized'
            ? 'Please sign in to manage your favorites'
            : res.error || (targetAction === 'remove' ? 'Failed to remove from favorites' : 'Failed to add to favorites')
        );
      }
    } catch {
      const offline = isOffline || (typeof navigator !== 'undefined' && !navigator.onLine);
      if (offline) {
        setStatus('offline_pending');
        setFeedbackSuccessText('Saved offline — will sync automatically when back online.');
      } else {
        // Rollback on non-offline unexpected error
        setIsFavorite(currentlyFav);
        setStatus('error');
        setErrorMessage('Network connection issue. Please check your connection and try again.');
      }
    }
  };

  const handleFeedback = async (
    interaction: 'like' | 'dislike' | 'favorite' | 'want_to_read' | 'reading' | 'finished'
  ) => {
    if (interaction === 'favorite') {
      return handleFavoriteToggle();
    }

    const isClearing = activeFeedback === interaction;
    const targetInteraction = isClearing ? 'clear' : interaction;
    const previousFeedback = activeFeedback;

    // Optimistic update for feedback / reading status - does NOT touch isFavorite!
    setActiveFeedback(isClearing ? null : interaction);
    setStatus('loading');
    setErrorMessage(null);
    setFeedbackSuccessText(null);

    try {
      const res = await submitFeedbackAction(bookId, targetInteraction);
      if (res.success) {
        setStatus('success');
        setFeedbackSuccessText(
          isClearing ? 'Status cleared! Recommendations updated.' : 'Preference saved! Recommendations updated.'
        );
      } else {
        setActiveFeedback(previousFeedback);
        setStatus('error');
        setErrorMessage(
          res.error === 'Unauthorized'
            ? 'Please sign in to save feedback'
            : res.error || (isClearing ? 'Failed to clear status' : 'Failed to save feedback')
        );
      }
    } catch {
      const offline = isOffline || (typeof navigator !== 'undefined' && !navigator.onLine);
      if (offline) {
        setStatus('offline_pending');
        setFeedbackSuccessText('Saved offline — will sync automatically when back online.');
      } else {
        setActiveFeedback(previousFeedback);
        setStatus('error');
        setErrorMessage('Network connection issue. Please check your connection and try again.');
      }
    }
  };

  const handleRemoveFromLibrary = async () => {
    const previousFav = isFavorite;
    const previousFeedback = activeFeedback;

    // Optimistic removal of all library and feedback associations
    setIsFavorite(false);
    setActiveFeedback(null);
    setStatus('loading');
    setErrorMessage(null);
    setFeedbackSuccessText(null);

    try {
      const res = await removeLibraryItem(bookId);
      if (res.success) {
        setStatus('success');
        setFeedbackSuccessText('Removed completely from your library.');
      } else {
        // Rollback both states on failure
        setIsFavorite(previousFav);
        setActiveFeedback(previousFeedback);
        setStatus('error');
        setErrorMessage(
          res.error === 'Unauthorized'
            ? 'Please sign in to manage your library'
            : res.error || 'Failed to remove from library'
        );
      }
    } catch {
      const offline = isOffline || (typeof navigator !== 'undefined' && !navigator.onLine);
      if (offline) {
        setStatus('offline_pending');
        setFeedbackSuccessText('Removal saved offline — will sync when back online.');
      } else {
        setIsFavorite(previousFav);
        setActiveFeedback(previousFeedback);
        setStatus('error');
        setErrorMessage('Network connection issue. Please check your connection and try again.');
      }
    }
  };

  return (
    <div
      className="glass-panel"
      style={{
        marginTop: '2rem',
        padding: '1.25rem 1.5rem',
        borderRadius: '16px',
        border: '1px solid var(--card-border)',
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '0.75rem', marginBottom: '1rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', flexWrap: 'wrap' }}>
          <h3 style={{ fontSize: '1.1rem', margin: 0, fontWeight: 600 }}>{t('feedback_title')}</h3>
          {activeFeedback === 'reading' && (
            <span style={{ fontSize: '0.75rem', padding: '0.2rem 0.6rem', borderRadius: '9999px', background: 'rgba(245, 158, 11, 0.2)', color: '#fbbf24', border: '1px solid rgba(245, 158, 11, 0.3)' }}>
              {t('feedback_currently_reading')}
            </span>
          )}
          {activeFeedback === 'finished' && (
            <span style={{ fontSize: '0.75rem', padding: '0.2rem 0.6rem', borderRadius: '9999px', background: 'rgba(16, 185, 129, 0.2)', color: 'var(--success)', border: '1px solid rgba(16, 185, 129, 0.3)' }}>
              {t('feedback_finished_reading')}
            </span>
          )}
        </div>
        <span style={{ fontSize: '0.8rem', color: 'var(--muted)' }}>
          {t('feedback_shapes_recs')}
        </span>
      </div>

      <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap' }}>
        <button
          type="button"
          onClick={handleFavoriteToggle}
          disabled={status === 'loading'}
          aria-label={isFavorite ? 'Remove from favorites' : 'Favorite book'}
          title={isFavorite ? 'Remove from favorites' : 'Add to favorites'}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.4rem',
            padding: '0.55rem 1rem',
            background: isFavorite ? 'rgba(236, 72, 153, 0.25)' : 'rgba(255, 255, 255, 0.05)',
            color: isFavorite ? '#f472b6' : 'var(--foreground)',
            border: isFavorite ? '1px solid #ec4899' : '1px solid var(--card-border)',
            borderRadius: '9999px',
            cursor: status === 'loading' ? 'not-allowed' : 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
        >
          <Heart size={16} fill={isFavorite ? '#f472b6' : 'none'} color={isFavorite ? '#f472b6' : 'currentColor'} />
          <span>{t('status_favorite')}</span>
        </button>

        <button
          type="button"
          onClick={() => handleFeedback('want_to_read')}
          disabled={status === 'loading'}
          aria-label={t('feedback_want_label')}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.4rem',
            padding: '0.55rem 1rem',
            background: activeFeedback === 'want_to_read' ? 'rgba(59, 130, 246, 0.25)' : 'rgba(255, 255, 255, 0.05)',
            color: activeFeedback === 'want_to_read' ? 'var(--primary)' : 'var(--foreground)',
            border: activeFeedback === 'want_to_read' ? '1px solid var(--primary)' : '1px solid var(--card-border)',
            borderRadius: '9999px',
            cursor: status === 'loading' ? 'not-allowed' : 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
        >
          <Bookmark size={16} fill={activeFeedback === 'want_to_read' ? 'currentColor' : 'none'} color={activeFeedback === 'want_to_read' ? 'var(--primary)' : 'currentColor'} />
          <span>{t('status_want_to_read')}</span>
        </button>

        <button
          type="button"
          onClick={() => handleFeedback('reading')}
          disabled={status === 'loading'}
          aria-label={t('feedback_reading_label')}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.4rem',
            padding: '0.55rem 1rem',
            background: activeFeedback === 'reading' ? 'rgba(245, 158, 11, 0.25)' : 'rgba(255, 255, 255, 0.05)',
            color: activeFeedback === 'reading' ? '#fbbf24' : 'var(--foreground)',
            border: activeFeedback === 'reading' ? '1px solid rgba(245, 158, 11, 0.5)' : '1px solid var(--card-border)',
            borderRadius: '9999px',
            cursor: status === 'loading' ? 'not-allowed' : 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
        >
          <BookOpen size={16} color={activeFeedback === 'reading' ? '#fbbf24' : 'currentColor'} />
          <span>{t('status_reading')}</span>
        </button>

        <button
          type="button"
          onClick={() => handleFeedback('finished')}
          disabled={status === 'loading'}
          aria-label={t('feedback_finished_label')}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.4rem',
            padding: '0.55rem 1rem',
            background: activeFeedback === 'finished' ? 'rgba(16, 185, 129, 0.25)' : 'rgba(255, 255, 255, 0.05)',
            color: activeFeedback === 'finished' ? 'var(--success)' : 'var(--foreground)',
            border: activeFeedback === 'finished' ? '1px solid var(--success)' : '1px solid var(--card-border)',
            borderRadius: '9999px',
            cursor: status === 'loading' ? 'not-allowed' : 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
        >
          <CheckCircle2 size={16} color={activeFeedback === 'finished' ? 'var(--success)' : 'currentColor'} />
          <span>{t('status_finished')}</span>
        </button>

        <button
          type="button"
          onClick={() => handleFeedback('like')}
          disabled={status === 'loading'}
          aria-label={t('feedback_like_label')}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.4rem',
            padding: '0.55rem 1rem',
            background: activeFeedback === 'like' ? 'rgba(16, 185, 129, 0.25)' : 'rgba(255, 255, 255, 0.05)',
            color: activeFeedback === 'like' ? 'var(--success)' : 'var(--foreground)',
            border: activeFeedback === 'like' ? '1px solid var(--success)' : '1px solid var(--card-border)',
            borderRadius: '9999px',
            cursor: status === 'loading' ? 'not-allowed' : 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
        >
          <ThumbsUp size={16} fill={activeFeedback === 'like' ? 'currentColor' : 'none'} color={activeFeedback === 'like' ? 'var(--success)' : 'currentColor'} />
          <span>{t('status_like')}</span>
        </button>

        <button
          type="button"
          onClick={() => handleFeedback('dislike')}
          disabled={status === 'loading'}
          aria-label={t('feedback_dislike_label')}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.4rem',
            padding: '0.55rem 1rem',
            background: activeFeedback === 'dislike' ? 'rgba(239, 68, 68, 0.25)' : 'rgba(255, 255, 255, 0.05)',
            color: activeFeedback === 'dislike' ? 'var(--danger)' : 'var(--foreground)',
            border: activeFeedback === 'dislike' ? '1px solid var(--danger)' : '1px solid var(--card-border)',
            borderRadius: '9999px',
            cursor: status === 'loading' ? 'not-allowed' : 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
        >
          <ThumbsDown size={16} fill={activeFeedback === 'dislike' ? 'currentColor' : 'none'} color={activeFeedback === 'dislike' ? 'var(--danger)' : 'currentColor'} />
          <span>{t('status_dislike')}</span>
        </button>

        {(isFavorite || activeFeedback) && (
          <button
            type="button"
            onClick={handleRemoveFromLibrary}
            disabled={status === 'loading'}
            aria-label={t('feedback_remove_title')}
            title={t('feedback_remove_label')}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.4rem',
              padding: '0.55rem 0.85rem',
              background: 'rgba(239, 68, 68, 0.1)',
              color: 'var(--danger)',
              border: '1px solid rgba(239, 68, 68, 0.25)',
              borderRadius: '9999px',
              cursor: status === 'loading' ? 'not-allowed' : 'pointer',
              fontSize: '0.8rem',
              fontWeight: 500,
              marginLeft: 'auto',
              transition: 'all 0.2s',
            }}
          >
            <Trash2 size={14} />
            <span>{t('remove_from_library')}</span>
          </button>
        )}
      </div>

      <div style={{ marginTop: '0.75rem', minHeight: '1.25rem' }}>
        {status === 'loading' && (
          <span style={{ color: 'var(--muted)', fontSize: '0.85rem' }} className="animate-pulse">
            {t('feedback_updating')}
          </span>
        )}
        {status === 'success' && (
          <span style={{ color: 'var(--success)', fontSize: '0.85rem', display: 'inline-flex', alignItems: 'center', gap: '0.35rem' }}>
            <Check size={14} />{' '}
            {feedbackSuccessText ||
              (isFavorite
                ? 'Added to favorites! Recommendations updated.'
                : 'Preference saved! Recommendations updated.')}
          </span>
        )}
        {status === 'offline_pending' && (
          <span style={{ color: '#fbbf24', fontSize: '0.85rem', display: 'inline-flex', alignItems: 'center', gap: '0.35rem' }}>
            <WifiOff size={14} />{' '}
            {feedbackSuccessText || 'Saved offline — will sync automatically when back online.'}
          </span>
        )}
        {status === 'error' && (
          <span style={{ color: 'var(--danger)', fontSize: '0.85rem', display: 'inline-flex', alignItems: 'center', gap: '0.35rem', flexWrap: 'wrap' }}>
            <AlertCircle size={14} style={{ flexShrink: 0 }} />
            <span>{errorMessage || 'Could not save feedback. Please try again.'}</span>
            {(errorMessage?.toLowerCase().includes('sign in') || errorMessage?.toLowerCase().includes('unauthorized')) && (
              <Link
                href={`/login?redirect=${encodeURIComponent(`/book/${bookId}`)}`}
                style={{
                  color: 'var(--primary)',
                  textDecoration: 'underline',
                  fontWeight: 600,
                  marginLeft: '0.35rem',
                }}
              >
                Sign in now &rarr;
              </Link>
            )}
          </span>
        )}
      </div>
    </div>
  );
}
