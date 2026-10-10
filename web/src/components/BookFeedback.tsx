'use client';

import { useState, useEffect, useRef } from 'react';
import { submitFeedbackAction, trackActivityAction } from '@/app/actions/user';

export default function BookFeedback({ bookId }: { bookId: string }) {
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [feedback, setFeedback] = useState<'like' | 'dislike' | null>(null);
  const hasTracked = useRef(false);

  useEffect(() => {
    // Track view once per component mount
    if (!hasTracked.current) {
      hasTracked.current = true;
      trackActivityAction(bookId, 'view').catch(console.error);
    }
  }, [bookId]);

  const handleFeedback = async (interaction: 'like' | 'dislike') => {
    setStatus('loading');
    const res = await submitFeedbackAction(bookId, interaction);
    if (res.success) {
      setStatus('success');
      setFeedback(interaction);
    } else {
      setStatus('error');
    }
  };

  return (
    <div className="book-feedback" style={{ marginTop: '2rem', padding: '1rem', background: 'rgba(255,255,255,0.05)', borderRadius: '12px' }}>
      <h3 style={{ margin: '0 0 1rem 0', fontSize: '1.1rem' }}>How did you like this book?</h3>
      <div style={{ display: 'flex', gap: '1rem', alignItems: 'center' }}>
        <button
          onClick={() => handleFeedback('like')}
          disabled={status === 'loading'}
          style={{
            padding: '0.5rem 1rem',
            background: feedback === 'like' ? 'var(--primary-color)' : 'transparent',
            color: feedback === 'like' ? '#fff' : 'var(--text-color)',
            border: '1px solid var(--primary-color)',
            borderRadius: '6px',
            cursor: 'pointer',
            transition: 'all 0.2s',
          }}
        >
          👍 Like
        </button>
        <button
          onClick={() => handleFeedback('dislike')}
          disabled={status === 'loading'}
          style={{
            padding: '0.5rem 1rem',
            background: feedback === 'dislike' ? 'var(--error-color)' : 'transparent',
            color: feedback === 'dislike' ? '#fff' : 'var(--text-color)',
            border: '1px solid var(--error-color)',
            borderRadius: '6px',
            cursor: 'pointer',
            transition: 'all 0.2s',
          }}
        >
          👎 Dislike
        </button>
        {status === 'success' && <span style={{ color: 'var(--success-color)', fontSize: '0.9rem' }}>Feedback saved!</span>}
        {status === 'error' && <span style={{ color: 'var(--error-color)', fontSize: '0.9rem' }}>Failed to save.</span>}
      </div>
    </div>
  );
}
