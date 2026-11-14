'use client';

import { useState } from 'react';
import Link from 'next/link';
import type { LibraryCollectionStatus, LibraryItem } from '@/types';
import { usePreferences } from '@/components/PreferencesProvider';
import { BookOpen, CheckCircle2, BookMarked, Play, RotateCcw, Trash2, Bookmark } from 'lucide-react';
import { BookCoverFallback } from './BookCoverFallback';

type ShelfTab = 'reading' | 'want_to_read' | 'finished';

export interface ReadingShelvesProps {
  readingBooks: LibraryItem[];
  wantToReadBooks: LibraryItem[];
  completedBooks: LibraryItem[];
  onUpdateStatus?: (bookId: string, status: LibraryCollectionStatus | 'clear') => void;
  isUpdating?: boolean;
}

/** Tabs with the reader's current, planned and finished books, plus quick status actions. */
export function ReadingShelves({
  readingBooks,
  wantToReadBooks,
  completedBooks,
  onUpdateStatus,
  isUpdating = false,
}: ReadingShelvesProps) {
  const { t } = usePreferences();
  const [activeShelfTab, setActiveShelfTab] = useState<ShelfTab>('reading');

  return (
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
                  {t('rj_none_reading')}
                  {wantToReadBooks.length > 0 ? (
                    <span style={{ display: 'block', marginTop: '0.25rem' }}>
                      {t('rj_want_waiting', { count: wantToReadBooks.length })}
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
                        aria-label={t('rj_remove_title_label', { title: book.title })}
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
  );
}
