'use client';

import { useState } from 'react';
import { BookCoverFallback } from './BookCoverFallback';

interface BookCoverImageProps {
  thumbnail?: string | null;
  title: string;
  authors?: string;
}

export function BookCoverImage({ thumbnail, title, authors }: BookCoverImageProps) {
  const [hasError, setHasError] = useState(false);

  const isValidThumbnail = Boolean(
    thumbnail &&
    thumbnail !== 'None' &&
    thumbnail.trim().length > 0 &&
    !thumbnail.includes('placehold.co') &&
    !thumbnail.includes('fallback-book.png')
  );

  const url = isValidThumbnail ? thumbnail!.replace('http:', 'https:') : null;

  if (!url || hasError) {
    return (
      <div style={{ width: '100%', minHeight: '380px', height: '100%', borderRadius: '16px', overflow: 'hidden' }}>
        <BookCoverFallback
          title={title}
          authors={authors}
          style={{ width: '100%', height: '100%', minHeight: '380px' }}
        />
      </div>
    );
  }

  return (
    /* eslint-disable-next-line @next/next/no-img-element */
    <img
      src={url}
      alt={title}
      style={{
        width: '100%',
        borderRadius: '16px',
        boxShadow: '0 12px 36px rgba(0,0,0,0.4)',
        objectFit: 'cover',
      }}
      onError={() => setHasError(true)}
    />
  );
}
