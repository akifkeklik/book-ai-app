'use client';

import { useState } from 'react';
import Link from 'next/link';
import type { Book } from '@/types';
import { Star, Sparkles, Heart, Bookmark, BookOpen, CheckCircle } from 'lucide-react';
import { BookCoverFallback } from './BookCoverFallback';
import { usePreferences } from '@/components/PreferencesProvider';
import { localizeRecommendationReason } from '@/lib/i18n';
import { formatCount, formatRating } from '@/lib/format';

interface BookCardProps {
  book: Book;
  userInteraction?: string | null;
  isFavorite?: boolean;
}

export function BookCard({ book, userInteraction, isFavorite }: BookCardProps) {
  const [imageError, setImageError] = useState(false);
  const { t, preferences } = usePreferences();

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

  const rawGenre = book.categories || '';
  const primaryGenre = rawGenre.split(/[,|]/)[0]?.trim();
  const authorDisplay = book.authors || t('unknown_author');
  const localizedReason = book.recommendationReason
    ? localizeRecommendationReason(book.recommendationReason, t)
    : null;

  return (
    <Link
      href={`/book/${book.isbn13}`}
      className="book-card animate-fade-in"
      aria-label={`${book.title} by ${authorDisplay}`}
    >
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
        {/* Visually distinct status badge */}
        {(isFavorite || userInteraction) && (
          <div
            style={{
              position: 'absolute',
              top: 8,
              left: 8,
              zIndex: 3,
              display: 'flex',
              flexDirection: 'column',
              gap: '4px',
            }}
          >
            {isFavorite && (
              <span className="status-badge status-badge-favorite" style={{ fontSize: '0.65rem', padding: '2px 7px' }}>
                <Heart size={11} fill="#f472b6" /> {t('status_favorite')}
              </span>
            )}
            {userInteraction === 'want_to_read' && (
              <span className="status-badge status-badge-want-to-read" style={{ fontSize: '0.65rem', padding: '2px 7px' }}>
                <Bookmark size={11} fill="currentColor" /> {t('status_want_to_read')}
              </span>
            )}
            {userInteraction === 'reading' && (
              <span className="status-badge status-badge-reading" style={{ fontSize: '0.65rem', padding: '2px 7px' }}>
                <BookOpen size={11} /> {t('status_reading')}
              </span>
            )}
            {userInteraction === 'finished' && (
              <span className="status-badge status-badge-finished" style={{ fontSize: '0.65rem', padding: '2px 7px' }}>
                <CheckCircle size={11} /> {t('status_finished')}
              </span>
            )}
          </div>
        )}
        {book.similarityScore !== undefined && (
          <div
            style={{
              position: 'absolute',
              top: 8,
              right: 8,
              background: 'var(--accent)',
              color: 'var(--accent-foreground, #ffffff)',
              padding: '4px 8px',
              borderRadius: '12px',
              fontSize: '0.75rem',
              fontWeight: 700,
              zIndex: 2,
              boxShadow: '0 2px 8px rgba(0,0,0,0.25)',
            }}
          >
            {t('percent_match', { percent: Math.round(book.similarityScore * 100) })}
          </div>
        )}
        {primaryGenre && (
          <div
            style={{
              position: 'absolute',
              bottom: 8,
              left: 8,
              background: 'rgba(0, 0, 0, 0.65)',
              backdropFilter: 'blur(6px)',
              WebkitBackdropFilter: 'blur(6px)',
              color: '#ffffff',
              padding: '2px 8px',
              borderRadius: '6px',
              fontSize: '0.65rem',
              fontWeight: 600,
              textTransform: 'uppercase',
              letterSpacing: '0.04em',
              maxWidth: '85%',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              zIndex: 2,
            }}
          >
            {primaryGenre}
          </div>
        )}
      </div>
      <div>
        <h3 className="book-title" title={book.title}>{book.title}</h3>
        <p className="book-author" title={authorDisplay}>{authorDisplay}</p>
        
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginTop: '4px' }}>
          <Star size={14} color="var(--rating)" fill="var(--rating)" aria-hidden="true" />
          <span style={{ fontSize: '0.875rem', color: 'var(--muted)' }}>
            {book.averageRating > 0 ? formatRating(book.averageRating, preferences.language) : t('no_rating')} 
            {book.ratingsCount > 0 && ` (${formatCount(book.ratingsCount, preferences.language, true)})`}
          </span>
        </div>

        {localizedReason && (
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '4px',
              marginTop: '6px',
              padding: '3px 8px',
              background: 'rgba(139, 92, 246, 0.1)',
              borderRadius: '6px',
              border: '1px solid rgba(139, 92, 246, 0.2)',
            }}
            title={localizedReason}
          >
            <Sparkles size={11} color="var(--accent)" style={{ flexShrink: 0 }} />
            <p
              style={{
                fontSize: '0.75rem',
                color: 'var(--accent)',
                fontStyle: 'italic',
                fontWeight: 500,
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
                margin: 0,
              }}
            >
              {localizedReason}
            </p>
          </div>
        )}
      </div>
    </Link>
  );
}


