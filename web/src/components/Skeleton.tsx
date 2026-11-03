import React from 'react';

interface SkeletonProps {
  width?: string | number;
  height?: string | number;
  borderRadius?: string | number;
  className?: string;
  style?: React.CSSProperties;
}

export function Skeleton({
  width = '100%',
  height = '1rem',
  borderRadius = '8px',
  className = '',
  style = {},
}: SkeletonProps) {
  return (
    <div
      className={`skeleton ${className}`.trim()}
      style={{
        width,
        height,
        borderRadius,
        ...style,
      }}
      aria-hidden="true"
    />
  );
}

export function BookCardSkeleton() {
  return (
    <div className="book-card-skeleton animate-fade-in" aria-hidden="true">
      <div className="cover-skeleton skeleton" />
      <div className="title-skeleton skeleton" />
      <div className="author-skeleton skeleton" />
      <div className="rating-skeleton skeleton" />
    </div>
  );
}

export function BookGridSkeleton({ count = 8 }: { count?: number }) {
  return (
    <div className="grid-books" aria-label="Loading books..." role="status">
      {Array.from({ length: count }).map((_, i) => (
        <BookCardSkeleton key={i} />
      ))}
    </div>
  );
}

export function BookDetailSkeleton() {
  return (
    <div className="container animate-fade-in" style={{ paddingBottom: '5rem' }} aria-label="Loading book details..." role="status">
      <div style={{ marginBottom: '2rem' }}>
        <Skeleton width="120px" height="36px" borderRadius="8px" />
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'minmax(260px, 340px) 1fr',
          gap: '3.5rem',
          alignItems: 'start',
        }}
      >
        {/* Cover column */}
        <div>
          <div className="skeleton" style={{ width: '100%', paddingTop: '150%', borderRadius: '16px' }} />
          <div style={{ marginTop: '1.5rem', display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
            <Skeleton height="48px" borderRadius="12px" />
            <Skeleton height="44px" borderRadius="12px" />
          </div>
        </div>

        {/* Info column */}
        <div>
          <Skeleton width="40%" height="2.5rem" style={{ marginBottom: '1rem' }} />
          <Skeleton width="25%" height="1.25rem" style={{ marginBottom: '1.5rem' }} />
          <div style={{ display: 'flex', gap: '1rem', marginBottom: '2rem' }}>
            <Skeleton width="100px" height="32px" borderRadius="9999px" />
            <Skeleton width="120px" height="32px" borderRadius="9999px" />
            <Skeleton width="90px" height="32px" borderRadius="9999px" />
          </div>
          <Skeleton width="100%" height="1rem" style={{ marginBottom: '0.75rem' }} />
          <Skeleton width="95%" height="1rem" style={{ marginBottom: '0.75rem' }} />
          <Skeleton width="90%" height="1rem" style={{ marginBottom: '0.75rem' }} />
          <Skeleton width="70%" height="1rem" style={{ marginBottom: '2.5rem' }} />

          <Skeleton width="30%" height="1.75rem" style={{ marginBottom: '1.5rem' }} />
          <div className="grid-books">
            {Array.from({ length: 4 }).map((_, i) => (
              <BookCardSkeleton key={i} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
