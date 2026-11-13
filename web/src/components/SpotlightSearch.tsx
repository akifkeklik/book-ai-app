'use client';

import React, { useEffect, useState, useRef, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { Search, X, Loader2, ArrowRight, Star, BookOpen, AlertCircle } from 'lucide-react';
import { searchCatalogAction } from '@/app/actions/catalog';
import type { Book } from '@/types';
import { usePreferences } from './PreferencesProvider';
import { BookCoverFallback } from './BookCoverFallback';

export function SpotlightSearch() {
  const router = useRouter();
  const { t } = usePreferences();

  const [isOpen, setIsOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Book[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedIndex, setSelectedIndex] = useState(0);

  const inputRef = useRef<HTMLInputElement>(null);
  const triggerRef = useRef<HTMLElement | null>(null);
  const abortControllerRef = useRef<AbortController | null>(null);
  const dialogRef = useRef<HTMLDivElement>(null);

  // Open & Close Handlers
  const openSpotlight = useCallback(() => {
    triggerRef.current = document.activeElement as HTMLElement | null;
    setIsOpen(true);
    setQuery('');
    setResults([]);
    setError(null);
    setSelectedIndex(0);
  }, []);

  const closeSpotlight = useCallback(() => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    setIsOpen(false);
    if (triggerRef.current && typeof triggerRef.current.focus === 'function') {
      triggerRef.current.focus();
    }
  }, []);

  // Global Keyboard Shortcuts (Cmd+K, Ctrl+K, Escape) & Custom Event
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        if (isOpen) {
          closeSpotlight();
        } else {
          openSpotlight();
        }
      } else if (e.key === 'Escape' && isOpen) {
        e.preventDefault();
        closeSpotlight();
      }
    };

    const handleCustomOpen = () => {
      openSpotlight();
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('open-spotlight', handleCustomOpen);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('open-spotlight', handleCustomOpen);
    };
  }, [isOpen, openSpotlight, closeSpotlight]);

  // Auto-focus input when opened
  useEffect(() => {
    if (isOpen) {
      // Small delay to allow DOM render
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 50);
      return () => clearTimeout(timer);
    }
  }, [isOpen]);

  // Focus trap inside dialog
  useEffect(() => {
    if (!isOpen) return;

    const handleFocusTrap = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return;

      const dialog = dialogRef.current;
      if (!dialog) return;

      const focusable = dialog.querySelectorAll<HTMLElement>(
        'input, button, [tabindex]:not([tabindex="-1"])'
      );
      if (focusable.length === 0) return;

      const first = focusable[0];
      const last = focusable[focusable.length - 1];

      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };

    window.addEventListener('keydown', handleFocusTrap);
    return () => window.removeEventListener('keydown', handleFocusTrap);
  }, [isOpen]);

  // Search execution with debouncing and stale-request cancellation
  useEffect(() => {
    const trimmed = query.trim();

    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }

    if (!trimmed) {
      const resetTimer = setTimeout(() => {
        setResults([]);
        setLoading(false);
        setError(null);
        setSelectedIndex(0);
      }, 0);
      return () => clearTimeout(resetTimer);
    }

    const controller = new AbortController();
    abortControllerRef.current = controller;

    const debounceTimer = setTimeout(async () => {
      setLoading(true);
      setError(null);
      try {
        const data = await searchCatalogAction(trimmed, 8);

        if (!controller.signal.aborted) {
          if (data.success) {
            setResults(data.books || []);
            setSelectedIndex(0);
          } else {
            setError(data.error || 'Failed to search catalog');
          }
          setLoading(false);
        }
      } catch (err: unknown) {
        if (controller.signal.aborted) return;
        setError(err instanceof Error ? err.message : 'Failed to search catalog');
        setLoading(false);
      }
    }, 220);

    return () => {
      clearTimeout(debounceTimer);
      controller.abort();
    };
  }, [query]);

  // Navigate to book
  const handleSelectBook = (book: Book) => {
    closeSpotlight();
    router.push(`/book/${book.isbn13}`);
  };

  // Keyboard navigation through results
  const handleInputKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (results.length > 0) {
        setSelectedIndex((prev) => (prev + 1) % results.length);
      }
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (results.length > 0) {
        setSelectedIndex((prev) => (prev - 1 + results.length) % results.length);
      }
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (results.length > 0 && results[selectedIndex]) {
        handleSelectBook(results[selectedIndex]);
      } else if (query.trim()) {
        closeSpotlight();
        router.push(`/catalog?q=${encodeURIComponent(query.trim())}`);
      }
    }
  };

  if (!isOpen) return null;

  return (
    <div
      className="spotlight-overlay"
      role="presentation"
      onClick={(e) => {
        if (e.target === e.currentTarget) closeSpotlight();
      }}
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        width: '100vw',
        height: '100vh',
        backgroundColor: 'rgba(0, 0, 0, 0.72)',
        backdropFilter: 'blur(8px)',
        WebkitBackdropFilter: 'blur(8px)',
        zIndex: 1000,
        display: 'flex',
        alignItems: 'flex-start',
        justifyContent: 'center',
        padding: '12vh 1rem 2rem',
        animation: 'fadeIn 0.15s ease-out',
      }}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-label={t('search') || t('spot_search_label')}
        className="glass-panel spotlight-dialog"
        style={{
          width: '100%',
          maxWidth: '640px',
          borderRadius: '16px',
          padding: 0,
          overflow: 'hidden',
          boxShadow: '0 24px 64px -12px rgba(0, 0, 0, 0.65), 0 0 0 1px var(--card-border)',
          background: 'var(--surface)',
        }}
      >
        {/* Search Input Bar */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.75rem',
            padding: '1rem 1.25rem',
            borderBottom: '1px solid var(--divider)',
          }}
        >
          <Search size={20} color="var(--primary)" style={{ flexShrink: 0 }} />
          <input
            ref={inputRef}
            id="spotlight-search-input"
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleInputKeyDown}
            placeholder={`${t('search')} titles, authors, genres, or ISBN...`}
            aria-label={t('spot_search_label')}
            aria-autocomplete="list"
            aria-controls="spotlight-results-list"
            aria-activedescendant={results[selectedIndex] ? `spotlight-item-${results[selectedIndex].isbn13}` : undefined}
            style={{
              flex: 1,
              background: 'transparent',
              border: 'none',
              outline: 'none',
              color: 'var(--foreground)',
              fontSize: '1.05rem',
              fontFamily: 'var(--font-body)',
            }}
          />
          {loading && <Loader2 size={18} className="animate-spin" color="var(--primary)" />}
          {query && !loading && (
            <button
              type="button"
              onClick={() => {
                setQuery('');
                inputRef.current?.focus();
              }}
              aria-label={t('clear_search')}
              style={{
                background: 'transparent',
                border: 'none',
                color: 'var(--text-muted)',
                cursor: 'pointer',
                display: 'flex',
                padding: '2px',
              }}
            >
              <X size={16} />
            </button>
          )}
          <button
            type="button"
            onClick={closeSpotlight}
            aria-label={t('spot_close')}
            style={{
              background: 'rgba(255, 255, 255, 0.08)',
              border: '1px solid var(--card-border)',
              borderRadius: '6px',
              color: 'var(--text-muted)',
              fontSize: '0.75rem',
              padding: '2px 6px',
              cursor: 'pointer',
              fontFamily: 'var(--font-mono)',
            }}
          >
            ESC
          </button>
        </div>

        {/* Results / Empty / Error List */}
        <div
          id="spotlight-results-list"
          role="listbox"
          aria-label={t('spot_suggestions')}
          style={{
            maxHeight: '400px',
            overflowY: 'auto',
            padding: '0.5rem',
          }}
        >
          {error && (
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '0.75rem',
                padding: '1.5rem',
                color: 'var(--danger)',
                fontSize: '0.9rem',
              }}
            >
              <AlertCircle size={20} />
              <span>{error}</span>
            </div>
          )}

          {!error && !loading && query.trim() && results.length === 0 && (
            <div
              style={{
                textAlign: 'center',
                padding: '2.5rem 1.5rem',
                color: 'var(--text-muted)',
              }}
            >
              <BookOpen size={36} style={{ margin: '0 auto 0.75rem', opacity: 0.4 }} />
              <p style={{ fontWeight: 600, fontSize: '0.95rem', color: 'var(--foreground)' }}>
                {t('no_books_found') || 'No books found'}
              </p>
              <p style={{ fontSize: '0.85rem', marginTop: '0.25rem' }}>
                No titles or authors match &ldquo;{query}&rdquo;
              </p>
            </div>
          )}

          {!error && !loading && !query.trim() && (
            <div
              style={{
                padding: '1.75rem 1.25rem',
                color: 'var(--text-muted)',
                fontSize: '0.85rem',
                lineHeight: '1.6',
              }}
            >
              <p style={{ fontWeight: 600, color: 'var(--foreground)', marginBottom: '0.5rem' }}>
                {t('spot_tips')}
              </p>
              <ul style={{ paddingLeft: '1.25rem', margin: 0 }}>
                <li>{t('spot_tip_title')}</li>
                <li>{t('spot_tip_isbn')}</li>
                <li>{t('spot_tip_keys')}</li>
              </ul>
            </div>
          )}

          {results.map((book, idx) => {
            const isSelected = idx === selectedIndex;
            return (
              <div
                key={book.isbn13}
                id={`spotlight-item-${book.isbn13}`}
                role="option"
                aria-selected={isSelected}
                onClick={() => handleSelectBook(book)}
                onMouseEnter={() => setSelectedIndex(idx)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '0.85rem',
                  padding: '0.65rem 0.85rem',
                  borderRadius: '10px',
                  cursor: 'pointer',
                  background: isSelected ? 'var(--card-hover, rgba(255, 255, 255, 0.08))' : 'transparent',
                  border: isSelected ? '1px solid var(--border)' : '1px solid transparent',
                  transition: 'background 0.15s ease',
                }}
              >
                {/* Thumbnail */}
                <div
                  style={{
                    width: '36px',
                    height: '52px',
                    borderRadius: '4px',
                    overflow: 'hidden',
                    flexShrink: 0,
                    position: 'relative',
                    background: 'var(--surface-elevated)',
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
                </div>

                {/* Details */}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div
                    style={{
                      fontWeight: 600,
                      fontSize: '0.92rem',
                      color: 'var(--foreground)',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                    }}
                  >
                    {book.title}
                  </div>
                  <div
                    style={{
                      fontSize: '0.8rem',
                      color: 'var(--text-muted)',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                      display: 'flex',
                      gap: '0.5rem',
                      alignItems: 'center',
                      marginTop: '2px',
                    }}
                  >
                    <span>{book.authors || 'Unknown Author'}</span>
                    {book.categories && (
                      <>
                        <span>•</span>
                        <span>{book.categories.split(/[,|]/)[0]?.trim()}</span>
                      </>
                    )}
                  </div>
                </div>

                {/* Rating & Action Icon */}
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', flexShrink: 0 }}>
                  {book.averageRating > 0 && (
                    <div
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: '2px',
                        fontSize: '0.75rem',
                        fontWeight: 600,
                        color: 'var(--rating)',
                      }}
                    >
                      <Star size={12} fill="currentColor" />
                      <span>{book.averageRating.toFixed(1)}</span>
                    </div>
                  )}
                  <ArrowRight
                    size={16}
                    color={isSelected ? 'var(--primary)' : 'var(--text-muted)'}
                    style={{
                      transform: isSelected ? 'translateX(2px)' : 'none',
                      transition: 'transform 0.15s ease, color 0.15s ease',
                    }}
                  />
                </div>
              </div>
            );
          })}
        </div>

        {/* Footer shortcuts helper */}
        {results.length > 0 && (
          <div
            style={{
              padding: '0.65rem 1rem',
              borderTop: '1px solid var(--divider)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              fontSize: '0.75rem',
              color: 'var(--text-muted)',
              background: 'var(--surface-subtle)',
            }}
          >
            <span>
              Press <kbd style={{ fontFamily: 'var(--font-mono)' }}>Enter</kbd> to open
            </span>
            <button
              type="button"
              onClick={() => {
                closeSpotlight();
                router.push(`/catalog?q=${encodeURIComponent(query.trim())}`);
              }}
              style={{
                background: 'transparent',
                border: 'none',
                color: 'var(--primary)',
                cursor: 'pointer',
                fontSize: '0.75rem',
                fontWeight: 600,
              }}
            >
              {t('spot_see_all')}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
