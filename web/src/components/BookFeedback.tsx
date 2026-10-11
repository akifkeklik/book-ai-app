'use client';

import { useState, useEffect, useRef } from 'react';
import { submitFeedbackAction, trackActivityAction } from '@/app/actions/user';
import { ThumbsUp, ThumbsDown, Heart, Bookmark, Check, AlertCircle } from 'lucide-react';

interface BookFeedbackProps {
  bookId: string;
}

export default function BookFeedback({ bookId }: BookFeedbackProps) {
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [activeFeedback, setActiveFeedback] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const hasTracked = useRef(false);

  useEffect(() => {
    // Track book view once per mount
    if (!hasTracked.current) {
      hasTracked.current = true;
      trackActivityAction(bookId, 'view').catch(() => {});
    }
  }, [bookId]);

  const handleFeedback = async (
    interaction: 'like' | 'dislike' | 'favorite' | 'want_to_read' | 'finished'
  ) => {
    setStatus('loading');
    setErrorMessage(null);
    try {
      const res = await submitFeedbackAction(bookId, interaction);
      if (res.success) {
        setStatus('success');
        setActiveFeedback(interaction);
      } else {
        setStatus('error');
        setErrorMessage(res.error || 'Failed to save feedback');
      }
    } catch {
      setStatus('error');
      setErrorMessage('Network error occurred');
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
        <h3 style={{ fontSize: '1.1rem', margin: 0, fontWeight: 600 }}>Your Reading Activity & Feedback</h3>
        <span style={{ fontSize: '0.8rem', color: 'var(--muted)' }}>
          Directly shapes your personalized recommendations
        </span>
      </div>

      <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap' }}>
        <button
          type="button"
          onClick={() => handleFeedback('favorite')}
          disabled={status === 'loading'}
          aria-label="Favorite book"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.4rem',
            padding: '0.55rem 1rem',
            background: activeFeedback === 'favorite' ? 'rgba(236, 72, 153, 0.25)' : 'rgba(255, 255, 255, 0.05)',
            color: activeFeedback === 'favorite' ? '#f472b6' : 'var(--foreground)',
            border: activeFeedback === 'favorite' ? '1px solid #ec4899' : '1px solid var(--card-border)',
            borderRadius: '9999px',
            cursor: status === 'loading' ? 'not-allowed' : 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
        >
          <Heart size={16} fill={activeFeedback === 'favorite' ? '#f472b6' : 'none'} color={activeFeedback === 'favorite' ? '#f472b6' : 'currentColor'} />
          <span>Favorite</span>
        </button>

        <button
          type="button"
          onClick={() => handleFeedback('want_to_read')}
          disabled={status === 'loading'}
          aria-label="Want to read book"
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
          <span>Want to Read</span>
        </button>

        <button
          type="button"
          onClick={() => handleFeedback('like')}
          disabled={status === 'loading'}
          aria-label="Like book"
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
          <span>Like</span>
        </button>

        <button
          type="button"
          onClick={() => handleFeedback('dislike')}
          disabled={status === 'loading'}
          aria-label="Dislike book"
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
          <span>Dislike</span>
        </button>
      </div>

      <div style={{ marginTop: '0.75rem', minHeight: '1.25rem' }}>
        {status === 'loading' && (
          <span style={{ color: 'var(--muted)', fontSize: '0.85rem' }} className="animate-pulse">
            Updating your preferences...
          </span>
        )}
        {status === 'success' && (
          <span style={{ color: 'var(--success)', fontSize: '0.85rem', display: 'inline-flex', alignItems: 'center', gap: '0.35rem' }}>
            <Check size={14} /> Preference saved! Recommendations updated.
          </span>
        )}
        {status === 'error' && (
          <span style={{ color: 'var(--danger)', fontSize: '0.85rem', display: 'inline-flex', alignItems: 'center', gap: '0.35rem' }}>
            <AlertCircle size={14} /> {errorMessage || 'Could not save feedback. Please try again.'}
          </span>
        )}
      </div>
    </div>
  );
}

