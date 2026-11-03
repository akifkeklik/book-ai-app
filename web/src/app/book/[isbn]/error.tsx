'use client';

import { useEffect } from 'react';
import Link from 'next/link';
import { AlertTriangle, ArrowLeft, RefreshCw } from 'lucide-react';

export default function BookDetailError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Log sanitized error message in development/monitoring without exposing stack to user
    console.error('Book detail render error:', error?.message || 'Unknown error');
  }, [error]);

  return (
    <div className="container" style={{ textAlign: 'center', padding: '6rem 2rem' }}>
      <div
        className="glass-panel"
        style={{
          maxWidth: '560px',
          margin: '0 auto',
          padding: '3rem 2rem',
          borderRadius: '16px',
        }}
      >
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: '64px',
            height: '64px',
            borderRadius: '50%',
            background: 'rgba(239, 68, 68, 0.15)',
            color: 'var(--danger, #ef4444)',
            marginBottom: '1.5rem',
          }}
        >
          <AlertTriangle size={32} />
        </div>

        <h2 style={{ fontSize: '1.75rem', marginBottom: '0.75rem' }}>
          Unable to Load Book Details
        </h2>

        <p className="text-muted" style={{ marginBottom: '2rem', lineHeight: '1.6' }}>
          We encountered an unexpected issue while retrieving this book. It might be a temporary
          network interruption or service unavailability. Please try again.
        </p>

        <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap' }}>
          <button
            type="button"
            onClick={() => reset()}
            className="btn btn-primary"
            style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem' }}
          >
            <RefreshCw size={16} /> Try Again
          </button>
          <Link
            href="/catalog"
            className="btn"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.5rem',
              background: 'rgba(255, 255, 255, 0.08)',
            }}
          >
            <ArrowLeft size={16} /> Back to Catalog
          </Link>
        </div>
      </div>
    </div>
  );
}
