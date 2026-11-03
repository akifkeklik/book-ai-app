'use client';

import { useState } from 'react';
import Link from 'next/link';
import type { Book, LibraryCollectionStatus } from '@/types';
import {
  Star,
  Sparkles,
  Heart,
  Bookmark,
  BookOpen,
  CheckCircle,
  ThumbsDown,
  Loader2,
} from 'lucide-react';
import { BookCoverFallback } from './BookCoverFallback';
import { usePreferences } from '@/components/PreferencesProvider';
import { localizeRecommendationReason, type TranslationKey } from '@/lib/i18n';

export interface PersonalizedDiscoveryCardProps {
  book: Book;
  isFavorite?: boolean;
  readingStatus?: LibraryCollectionStatus | null;
  isUpdating?: boolean;
  isDismissing?: boolean;
  onToggleFavorite: (bookId: string) => void;
  onUpdateShelf: (bookId: string, status: LibraryCollectionStatus | 'clear') => void;
  onDismiss: (book: Book) => void;
}

export function PersonalizedDiscoveryCard({
  book,
  isFavorite = false,
  readingStatus = null,
  isUpdating = false,
  isDismissing = false,
  onToggleFavorite,
  onUpdateShelf,
  onDismiss,
}: PersonalizedDiscoveryCardProps) {
  const [imageError, setImageError] = useState(false);
  const { t } = usePreferences();

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
    : book.explanation || null;

  return (
    <div
      className="glass-panel animate-fade-in"
      style={{
        display: 'flex',
        flexDirection: 'column',
        borderRadius: '16px',
        overflow: 'hidden',
        border: '1px solid var(--card-border)',
        opacity: isDismissing ? 0.4 : isUpdating ? 0.7 : 1,
        transition: 'all 0.25s ease',
        position: 'relative',
        background: 'var(--card-bg, rgba(255, 255, 255, 0.03))',
      }}
      data-isbn={book.isbn13}
    >
      {/* Clickable Book Cover & Header Area */}
      <Link
        href={`/book/${book.isbn13}`}
        style={{ textDecoration: 'none', color: 'inherit', display: 'block' }}
        aria-label={`${book.title} by ${authorDisplay}`}
      >
        <div className="book-cover-container" style={{ position: 'relative', height: '260px' }}>
          {!thumbnailUrl || imageError ? (
            <BookCoverFallback
              title={book.title}
              authors={book.authors}
              className="book-cover-fallback"
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
              style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            />
          )}

          {/* Active Shelf Status Badges */}
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
              <span
                className="status-badge status-badge-favorite"
                style={{ fontSize: '0.65rem', padding: '2px 7px' }}
              >
                <Heart size={11} fill="#f472b6" /> {t('status_favorite')}
              </span>
            )}
            {readingStatus === 'want_to_read' && (
              <span
                className="status-badge status-badge-want-to-read"
                style={{ fontSize: '0.65rem', padding: '2px 7px' }}
              >
                <Bookmark size={11} fill="currentColor" /> {t('status_want_to_read')}
              </span>
            )}
            {readingStatus === 'reading' && (
              <span
                className="status-badge status-badge-reading"
                style={{ fontSize: '0.65rem', padding: '2px 7px' }}
              >
                <BookOpen size={11} /> {t('status_reading')}
              </span>
            )}
            {readingStatus === 'finished' && (
              <span
                className="status-badge status-badge-finished"
                style={{ fontSize: '0.65rem', padding: '2px 7px' }}
              >
                <CheckCircle size={11} /> {t('status_finished')}
              </span>
            )}
          </div>

          {/* Similarity / Match Score Badge & Confidence */}
          <div
            style={{
              position: 'absolute',
              top: 8,
              right: 8,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'flex-end',
              gap: '4px',
              zIndex: 2,
            }}
          >
            {book.similarityScore !== undefined && (
              <div
                style={{
                  background: 'var(--accent)',
                  color: 'var(--accent-foreground, #ffffff)',
                  padding: '4px 8px',
                  borderRadius: '12px',
                  fontSize: '0.75rem',
                  fontWeight: 700,
                  boxShadow: '0 2px 8px rgba(0,0,0,0.25)',
                }}
              >
                {t('percent_match', { percent: Math.round(book.similarityScore * 100) })}
              </div>
            )}
            {book.confidence && (
              <div
                style={{
                  background: 'rgba(0, 0, 0, 0.72)',
                  backdropFilter: 'blur(4px)',
                  color: book.confidence === 'high' ? '#34d399' : book.confidence === 'cold_start' ? '#fbbf24' : '#93c5fd',
                  padding: '2px 6px',
                  borderRadius: '6px',
                  fontSize: '0.65rem',
                  fontWeight: 600,
                  border: '1px solid rgba(255, 255, 255, 0.12)',
                }}
              >
                {t(`confidence_${book.confidence}` as TranslationKey) || book.confidence}
              </div>
            )}
          </div>

          {/* Primary Genre Tag */}
          {primaryGenre && (
            <div
              style={{
                position: 'absolute',
                bottom: 8,
                left: 8,
                background: 'rgba(0, 0, 0, 0.72)',
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
      </Link>

      {/* Book Metadata Area */}
      <div style={{ padding: '1rem', display: 'flex', flexDirection: 'column', flex: 1, gap: '0.5rem' }}>
        <Link
          href={`/book/${book.isbn13}`}
          style={{ textDecoration: 'none', color: 'inherit' }}
        >
          <h3
            className="book-title"
            title={book.title}
            style={{ fontSize: '1.05rem', margin: '0 0 0.25rem', lineHeight: '1.3' }}
          >
            {book.title}
          </h3>
        </Link>

        <p
          className="book-author"
          title={authorDisplay}
          style={{ fontSize: '0.875rem', color: 'var(--muted)', margin: 0 }}
        >
          {authorDisplay}
        </p>

        {/* Rating Row */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
          <Star size={14} color="var(--rating)" fill="var(--rating)" aria-hidden="true" />
          <span style={{ fontSize: '0.85rem', color: 'var(--muted)' }}>
            {book.averageRating > 0 ? book.averageRating.toFixed(1) : t('no_rating')}
            {book.ratingsCount > 0 && ` (${book.ratingsCount})`}
          </span>
        </div>

        {/* Transparent Attribution / Recommendation Reason */}
        {localizedReason && (
          <div
            style={{
              display: 'flex',
              alignItems: 'flex-start',
              gap: '6px',
              padding: '6px 10px',
              background: 'rgba(139, 92, 246, 0.09)',
              borderRadius: '8px',
              border: '1px solid rgba(139, 92, 246, 0.22)',
              marginTop: 'auto',
            }}
            title={localizedReason}
          >
            <Sparkles size={13} color="var(--accent)" style={{ flexShrink: 0, marginTop: '2px' }} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: '2px', flex: 1 }}>
              {book.explanationType && (
                <span
                  style={{
                    fontSize: '0.65rem',
                    fontWeight: 700,
                    textTransform: 'uppercase',
                    letterSpacing: '0.04em',
                    color: 'var(--accent)',
                  }}
                >
                  {t(`exp_type_${book.explanationType}` as TranslationKey) || book.explanationType}
                </span>
              )}
              <p
                style={{
                  fontSize: '0.78rem',
                  color: 'var(--accent)',
                  fontWeight: 500,
                  lineHeight: '1.35',
                  margin: 0,
                }}
              >
                {localizedReason}
              </p>
            </div>
          </div>
        )}

        {/* Quick One-touch Reading Shelf Action */}
        <div style={{ display: 'flex', gap: '0.4rem', marginTop: '0.25rem' }}>
          {readingStatus === null && (
            <>
              <button
                type="button"
                onClick={(e) => {
                  e.preventDefault();
                  onUpdateShelf(book.isbn13, 'want_to_read');
                }}
                disabled={isUpdating || isDismissing}
                className="btn btn-outline"
                style={{
                  flex: 1,
                  padding: '0.35rem 0.5rem',
                  fontSize: '0.75rem',
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '4px',
                }}
                title={t('mark_as_want_to_read')}
                aria-label={`${t('mark_as_want_to_read')} - ${book.title}`}
              >
                <Bookmark size={13} />
                <span>{t('status_want_to_read')}</span>
              </button>
              <button
                type="button"
                onClick={(e) => {
                  e.preventDefault();
                  onUpdateShelf(book.isbn13, 'reading');
                }}
                disabled={isUpdating || isDismissing}
                className="btn btn-primary"
                style={{
                  flex: 1,
                  padding: '0.35rem 0.5rem',
                  fontSize: '0.75rem',
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '4px',
                }}
                title={t('mark_as_reading')}
                aria-label={`${t('mark_as_reading')} - ${book.title}`}
              >
                <BookOpen size={13} />
                <span>{t('status_reading')}</span>
              </button>
            </>
          )}

          {readingStatus === 'want_to_read' && (
            <button
              type="button"
              onClick={(e) => {
                e.preventDefault();
                onUpdateShelf(book.isbn13, 'reading');
              }}
              disabled={isUpdating || isDismissing}
              className="btn btn-primary"
              style={{
                width: '100%',
                padding: '0.35rem 0.5rem',
                fontSize: '0.75rem',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '4px',
              }}
              title={t('mark_as_reading')}
              aria-label={`${t('mark_as_reading')} - ${book.title}`}
            >
              <BookOpen size={13} />
              <span>{t('mark_as_reading')}</span>
            </button>
          )}

          {readingStatus === 'reading' && (
            <button
              type="button"
              onClick={(e) => {
                e.preventDefault();
                onUpdateShelf(book.isbn13, 'finished');
              }}
              disabled={isUpdating || isDismissing}
              className="btn btn-outline"
              style={{
                width: '100%',
                padding: '0.35rem 0.5rem',
                fontSize: '0.75rem',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '4px',
                color: 'var(--success, #10b981)',
                borderColor: 'rgba(16, 185, 129, 0.4)',
              }}
              title={t('mark_as_finished')}
              aria-label={`${t('mark_as_finished')} - ${book.title}`}
            >
              <CheckCircle size={13} />
              <span>{t('mark_as_finished')}</span>
            </button>
          )}

          {readingStatus === 'finished' && (
            <button
              type="button"
              onClick={(e) => {
                e.preventDefault();
                onUpdateShelf(book.isbn13, 'reading');
              }}
              disabled={isUpdating || isDismissing}
              className="btn btn-outline"
              style={{
                width: '100%',
                padding: '0.35rem 0.5rem',
                fontSize: '0.75rem',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '4px',
              }}
              title={t('mark_as_reading')}
              aria-label={`${t('mark_as_reading')} - ${book.title}`}
            >
              <BookOpen size={13} />
              <span>{t('status_reading')}</span>
            </button>
          )}
        </div>

        {/* Interactive Action Controls */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '0.5rem',
            paddingTop: '0.75rem',
            marginTop: '0.5rem',
            borderTop: '1px solid var(--card-border)',
          }}
        >
          {/* Favorite Toggle Button */}
          <button
            type="button"
            onClick={(e) => {
              e.preventDefault();
              onToggleFavorite(book.isbn13);
            }}
            disabled={isUpdating || isDismissing}
            className={`btn btn-outline ${isFavorite ? 'active' : ''}`}
            style={{
              padding: '0.35rem 0.65rem',
              fontSize: '0.75rem',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.35rem',
              color: isFavorite ? '#f472b6' : 'var(--foreground)',
              borderColor: isFavorite ? 'rgba(244, 114, 182, 0.4)' : undefined,
            }}
            title={isFavorite ? t('unfavorite') : t('add_to_favorites')}
            aria-label={isFavorite ? t('unfavorite') : t('add_to_favorites')}
          >
            <Heart size={14} fill={isFavorite ? '#f472b6' : 'none'} color="#f472b6" />
            <span style={{ fontSize: '0.75rem' }}>{isFavorite ? t('status_favorite') : t('add_to_favorites')}</span>
          </button>

          {/* Shelf Selector Dropdown */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
            <select
              value={readingStatus || 'clear'}
              onChange={(e) => {
                const val = e.target.value as LibraryCollectionStatus | 'clear';
                onUpdateShelf(book.isbn13, val);
              }}
              disabled={isUpdating || isDismissing}
              className="input-field"
              style={{
                height: '32px',
                fontSize: '0.75rem',
                padding: '0 0.5rem',
                cursor: 'pointer',
                borderRadius: '8px',
                border: '1px solid var(--card-border)',
                background: 'rgba(255, 255, 255, 0.05)',
              }}
              aria-label={`Select reading shelf for ${book.title}`}
            >
              <option value="clear">{t('reset')}</option>
              <option value="want_to_read">{t('status_want_to_read')}</option>
              <option value="reading">{t('status_reading')}</option>
              <option value="finished">{t('status_finished')}</option>
            </select>

            {/* "İlgilenmiyorum" / Dislike Button */}
            <button
              type="button"
              onClick={(e) => {
                e.preventDefault();
                onDismiss(book);
              }}
              disabled={isUpdating || isDismissing}
              className="btn btn-outline"
              style={{
                padding: '0.35rem 0.5rem',
                height: '32px',
                color: 'var(--muted)',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
              title={t('dismiss_recommendation')}
              aria-label={`${t('dismiss_recommendation')} - ${book.title}`}
            >
              {isDismissing ? (
                <Loader2 size={13} className="animate-spin" />
              ) : (
                <ThumbsDown size={13} />
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
