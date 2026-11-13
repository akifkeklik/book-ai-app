'use client';

import React, { useState, useTransition } from 'react';
import Link from 'next/link';
import type { Book } from '@/types';
import { BookCard } from '@/components/BookCard';
import { fetchCatalogPageAction } from '@/app/actions/catalog';
import { Loader2, ChevronDown, Check } from 'lucide-react';
import { buildCatalogUrl, type CatalogFilterState, type CatalogUrlOverrides } from '@/lib/catalogUrl';
import { usePreferences } from '@/components/PreferencesProvider';

interface CatalogBookListProps {
  initialBooks: Book[];
  initialPage: number;
  totalPages: number;
  totalBooks: number;
  filterParams: CatalogFilterState;
}

export function CatalogBookList({
  initialBooks,
  initialPage,
  totalPages,
  totalBooks,
  filterParams,
}: CatalogBookListProps) {
  const { t } = usePreferences();
  const createFilterUrl = (overrides: CatalogUrlOverrides) => buildCatalogUrl(filterParams, overrides);
  const [books, setBooks] = useState<Book[]>(initialBooks);
  const [currentPage, setCurrentPage] = useState<number>(initialPage);
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [statusMessage, setStatusMessage] = useState<string>('');

  const hasMore = currentPage < totalPages;

  const handleLoadMore = () => {
    if (!hasMore || isPending) return;

    setError(null);
    const nextPage = currentPage + 1;

    startTransition(async () => {
      try {
        const res = await fetchCatalogPageAction({
          page: nextPage,
          per_page: 20,
          category: filterParams.category,
          query: filterParams.query,
          sort: filterParams.sort,
          order: filterParams.order,
          min_rating: filterParams.min_rating,
        });

        if (res.success && res.data) {
          const newBooks = res.data.books || [];
          setBooks((prev) => [...prev, ...newBooks]);
          setCurrentPage(nextPage);
          setStatusMessage(`Loaded ${newBooks.length} more books. Now showing ${books.length + newBooks.length} of ${totalBooks} books.`);
        } else {
          setError(res.error || 'Failed to load more books. Please try again.');
        }
      } catch {
        setError(t('catalog_more_error'));
      }
    });
  };

  return (
    <div>
      {/* Screen reader live region for accessibility */}
      <div
        role="status"
        aria-live="polite"
        className="sr-only"
        style={{
          position: 'absolute',
          width: '1px',
          height: '1px',
          padding: 0,
          margin: '-1px',
          overflow: 'hidden',
          clip: 'rect(0, 0, 0, 0)',
          whiteSpace: 'nowrap',
          borderWidth: 0,
        }}
      >
        {statusMessage}
      </div>

      {/* Book Grid */}
      <div className="grid-books" id="catalog-books-grid">
        {books.map((book, idx) => (
          <BookCard key={`${book.isbn13}-${idx}`} book={book} />
        ))}
      </div>

      {/* Load More & Pagination Controls */}
      <div style={{ marginTop: '3.5rem', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '1.5rem' }}>
        {error && (
          <div
            role="alert"
            style={{
              padding: '0.75rem 1.25rem',
              borderRadius: '8px',
              backgroundColor: 'rgba(239, 68, 68, 0.12)',
              border: '1px solid rgba(239, 68, 68, 0.3)',
              color: '#f87171',
              fontSize: '0.9rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.75rem',
            }}
          >
            <span>{error}</span>
            <button
              onClick={handleLoadMore}
              className="btn btn-outline"
              style={{ padding: '0.25rem 0.75rem', fontSize: '0.8rem' }}
            >
              {t('retry')}
            </button>
          </div>
        )}

        {hasMore ? (
          <button
            type="button"
            id="catalog-load-more-btn"
            onClick={handleLoadMore}
            disabled={isPending}
            className="btn btn-primary"
            style={{
              padding: '0.85rem 2.25rem',
              fontSize: '1rem',
              fontWeight: 600,
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.6rem',
              boxShadow: '0 4px 14px rgba(0, 0, 0, 0.25)',
              cursor: isPending ? 'not-allowed' : 'pointer',
              opacity: isPending ? 0.75 : 1,
            }}
            aria-label={`Load more books. Page ${currentPage + 1} of ${totalPages}`}
          >
            {isPending ? (
              <>
                <Loader2 size={18} className="animate-spin" />
                <span>{t('catalog_loading_more')}</span>
              </>
            ) : (
              <>
                <ChevronDown size={18} />
                <span>Load More Books ({currentPage} / {totalPages})</span>
              </>
            )}
          </button>
        ) : totalPages > 1 ? (
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              color: 'var(--muted)',
              fontSize: '0.95rem',
              padding: '0.5rem 1rem',
              borderRadius: '9999px',
              background: 'rgba(255, 255, 255, 0.04)',
            }}
          >
            <Check size={16} color="var(--primary)" />
            <span>All {totalBooks} books displayed</span>
          </div>
        ) : null}

        {/* Direct page navigation for SSR, SEO, and accessible direct jumps */}
        {totalPages > 1 && (
          <nav
            aria-label={t('catalog_pages_label')}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '1rem',
              marginTop: '0.5rem',
              fontSize: '0.9rem',
              color: 'var(--muted)',
            }}
          >
            <Link
              href={createFilterUrl({ page: Math.max(1, currentPage - 1) })}
              className="btn btn-outline"
              style={{
                padding: '0.4rem 0.9rem',
                fontSize: '0.85rem',
                pointerEvents: currentPage <= 1 ? 'none' : 'auto',
                opacity: currentPage <= 1 ? 0.4 : 1,
              }}
            >
              {t('previous')}
            </Link>
            <span>
              Page <strong style={{ color: 'var(--foreground)' }}>{currentPage}</strong> of {totalPages}
            </span>
            <Link
              href={createFilterUrl({ page: Math.min(totalPages, currentPage + 1) })}
              className="btn btn-outline"
              style={{
                padding: '0.4rem 0.9rem',
                fontSize: '0.85rem',
                pointerEvents: currentPage >= totalPages ? 'none' : 'auto',
                opacity: currentPage >= totalPages ? 0.4 : 1,
              }}
            >
              {t('next')}
            </Link>
          </nav>
        )}
      </div>
    </div>
  );
}
