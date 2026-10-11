'use client';

import { useState } from 'react';
import Link from 'next/link';
import type { Book } from '@/types';
import { Star } from 'lucide-react';
import { BookCoverFallback } from './BookCoverFallback';

export function BookCard({ book }: { book: Book }) {
  const [imageError, setImageError] = useState(false);

  const hasValidThumbnail = Boolean(
    book.thumbnail &&
    book.thumbnail !== 'None' &&
    book.thumbnail.trim().length > 0 &&
    !book.thumbnail.includes('placehold.co') &&
    !book.thumbnail.includes('fallback-book.png')
  );

  const thumbnailUrl = hasValidThumbnail
    ? book.thumbnail.replace('http:', 'https:')
    : null;

  return (
    <Link href={`/book/${book.isbn13}`} className="book-card animate-fade-in">
      <div className="book-cover-container">
        {!thumbnailUrl || imageError ? (
          <BookCoverFallback
            title={book.title}
            authors={book.authors}
            style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%' }}
          />
        ) : (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img 
            src={thumbnailUrl} 
            alt={book.title}
            className="book-cover"
            onError={() => setImageError(true)}
            loading="lazy"
          />
        )}
        {book.similarityScore !== undefined && (
          <div style={{ position: 'absolute', top: 8, right: 8, background: 'var(--accent)', color: 'white', padding: '4px 8px', borderRadius: '12px', fontSize: '0.75rem', fontWeight: 'bold', zIndex: 2 }}>
            {Math.round(book.similarityScore * 100)}% Match
          </div>
        )}
      </div>
      <div>
        <h3 className="book-title" title={book.title}>{book.title}</h3>
        <p className="book-author" title={book.authors}>{book.authors || 'Unknown Author'}</p>
        
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginTop: '4px' }}>
          <Star size={14} color="#fbbf24" fill="#fbbf24" />
          <span style={{ fontSize: '0.875rem', color: 'var(--muted)' }}>
            {book.averageRating > 0 ? book.averageRating.toFixed(1) : 'No rating'} 
            {book.ratingsCount > 0 && ` (${book.ratingsCount})`}
          </span>
        </div>

        {book.recommendationReason && (
          <p
            style={{
              fontSize: '0.75rem',
              color: 'var(--accent)',
              marginTop: '4px',
              fontStyle: 'italic',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
            title={book.recommendationReason}
          >
            {book.recommendationReason}
          </p>
        )}
      </div>
    </Link>
  );
}

