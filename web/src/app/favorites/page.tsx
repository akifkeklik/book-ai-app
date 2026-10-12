'use client';

import { useEffect, useState, useTransition, useMemo } from 'react';
import Link from 'next/link';
import { useAuth } from '@/components/AuthProvider';
import {
  getLibraryBooks,
  removeLibraryItem,
  updateLibraryItemStatus,
} from '@/app/actions/library';
import type { LibraryCollectionStatus, LibraryItem } from '@/types';
import {
  Heart,
  Bookmark,
  CheckCircle,
  BookOpen,
  Trash2,
  AlertCircle,
  Search,
  Sparkles,
  Compass,
  Lock,
  ArrowUpDown,
  RefreshCw,
} from 'lucide-react';
import { BookCoverFallback } from '@/components/BookCoverFallback';

type FilterTab = 'all' | LibraryCollectionStatus;
type SortOption = 'recent' | 'title' | 'rating';

export default function FavoritesPage() {
  const { user, loading: authLoading } = useAuth();
  const [items, setItems] = useState<LibraryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<FilterTab>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<SortOption>('recent');
  const [updatingId, setUpdatingId] = useState<string | null>(null);
  const [, startTransition] = useTransition();

  const handleRefresh = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await getLibraryBooks();
      if (res.success) {
        setItems(res.items);
      } else {
        setError(res.error || 'Failed to load library items');
      }
    } catch {
      setError('An unexpected network error occurred while loading your library.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let ignore = false;

    if (!authLoading && user) {
      getLibraryBooks()
        .then((res) => {
          if (!ignore) {
            if (res.success) {
              setItems(res.items);
            } else {
              setError(res.error || 'Failed to load library items');
            }
            setLoading(false);
          }
        })
        .catch(() => {
          if (!ignore) {
            setError('An unexpected network error occurred while loading your library.');
            setLoading(false);
          }
        });
    }

    return () => {
      ignore = true;
    };
  }, [user, authLoading]);

  // Counts per status
  const counts = useMemo(() => {
    const total = items.length;
    const favorites = items.filter((i) => i.status === 'favorite').length;
    const wantToRead = items.filter((i) => i.status === 'want_to_read').length;
    const finished = items.filter((i) => i.status === 'finished').length;
    const reading = items.filter((i) => i.status === 'reading').length;
    return { total, favorites, wantToRead, finished, reading };
  }, [items]);

  // Filtered and sorted items
  const filteredItems = useMemo(() => {
    return items
      .filter((item) => {
        // Tab filter
        if (activeTab !== 'all' && item.status !== activeTab) {
          return false;
        }
        // Search query
        if (searchQuery.trim().length > 0) {
          const q = searchQuery.toLowerCase();
          const matchTitle = item.book.title?.toLowerCase().includes(q);
          const matchAuthor = item.book.authors?.toLowerCase().includes(q);
          return matchTitle || matchAuthor;
        }
        return true;
      })
      .sort((a, b) => {
        if (sortBy === 'title') {
          return (a.book.title || '').localeCompare(b.book.title || '');
        }
        if (sortBy === 'rating') {
          return (b.book.averageRating || 0) - (a.book.averageRating || 0);
        }
        // Default: recent (addedAt desc)
        return new Date(b.addedAt).getTime() - new Date(a.addedAt).getTime();
      });
  }, [items, activeTab, searchQuery, sortBy]);

  // Optimistic Remove with rollback
  const handleRemove = (bookId: string) => {
    const previousItems = [...items];
    setItems((prev) => prev.filter((i) => i.bookId !== bookId));
    setUpdatingId(bookId);
    setError(null);

    startTransition(async () => {
      try {
        const res = await removeLibraryItem(bookId);
        if (!res.success) {
          setItems(previousItems); // Rollback
          setError(res.error || 'Failed to remove item');
        }
      } catch {
        setItems(previousItems); // Rollback
        setError('Network error while removing book.');
      } finally {
        setUpdatingId(null);
      }
    });
  };

  // Optimistic Status Update with rollback
  const handleStatusChange = (bookId: string, newStatus: LibraryCollectionStatus) => {
    const previousItems = [...items];
    setItems((prev) =>
      prev.map((i) => (i.bookId === bookId ? { ...i, status: newStatus } : i))
    );
    setUpdatingId(bookId);
    setError(null);

    startTransition(async () => {
      try {
        const res = await updateLibraryItemStatus(bookId, newStatus);
        if (!res.success) {
          setItems(previousItems); // Rollback
          setError(res.error || 'Failed to update book status');
        }
      } catch {
        setItems(previousItems); // Rollback
        setError('Network error while updating status.');
      } finally {
        setUpdatingId(null);
      }
    });
  };

  // 1. Deliberate Unauthenticated State
  if (!authLoading && !user) {
    return (
      <main className="container" style={{ padding: '4rem 1rem', minHeight: '65vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div
          className="glass-panel text-center animate-fade-in"
          style={{ maxWidth: '520px', width: '100%', padding: '3rem 2rem' }}
        >
          <div
            style={{
              width: '64px',
              height: '64px',
              borderRadius: '50%',
              background: 'rgba(59, 130, 246, 0.15)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              margin: '0 auto 1.5rem',
            }}
          >
            <Lock size={32} color="var(--primary)" />
          </div>
          <h1 style={{ fontSize: '1.85rem', marginBottom: '0.75rem' }}>Sign In to Your Library</h1>
          <p className="text-muted" style={{ marginBottom: '2rem', fontSize: '0.95rem', lineHeight: '1.6' }}>
            Your personal library synchronizes your favorites, reading list, and reading history across all your devices. Sign in to access your curated collection.
          </p>
          <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center' }}>
            <Link href="/login?redirect=/favorites" className="btn btn-primary" id="library-login-btn">
              Log In to Libris
            </Link>
            <Link href="/signup" className="btn btn-outline">
              Create an Account
            </Link>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className="container" style={{ padding: '2rem 1rem 4rem' }}>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '1rem', marginBottom: '2rem' }}>
        <div>
          <h1 style={{ fontSize: '2.5rem', marginBottom: '0.25rem' }}>My Library</h1>
          <p className="text-muted" style={{ fontSize: '1rem' }}>
            Manage your personal sanctuary of books, reading lists, and favorites.
          </p>
        </div>
        <button
          onClick={handleRefresh}
          disabled={loading}
          className="btn btn-outline"
          style={{ padding: '0.5rem 1rem', fontSize: '0.85rem' }}
          title="Refresh Library"
          aria-label="Refresh library"
        >
          <RefreshCw size={15} className={loading ? 'animate-spin' : ''} />
          <span>Refresh</span>
        </button>
      </div>

      {/* Error Banner with Retry */}
      {error && (
        <div
          role="alert"
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '1rem 1.25rem',
            background: 'rgba(239, 68, 68, 0.12)',
            border: '1px solid rgba(239, 68, 68, 0.3)',
            color: 'var(--danger)',
            borderRadius: '12px',
            marginBottom: '1.5rem',
            fontSize: '0.9rem',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <AlertCircle size={18} />
            <span>{error}</span>
          </div>
          <button
            onClick={handleRefresh}
            className="btn btn-outline"
            style={{ padding: '0.35rem 0.75rem', fontSize: '0.8rem', borderColor: 'rgba(239, 68, 68, 0.4)' }}
          >
            Retry
          </button>
        </div>
      )}

      {/* Collection Tabs & Filter Bar */}
      <div
        className="glass-panel"
        style={{
          padding: '1.25rem',
          marginBottom: '2rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '1.25rem',
        }}
      >
        {/* Collection Filter Tabs */}
        <div className="library-tabs" role="tablist" aria-label="Library collections">
          <button
            role="tab"
            aria-selected={activeTab === 'all'}
            onClick={() => setActiveTab('all')}
            className={`library-tab-btn ${activeTab === 'all' ? 'active' : ''}`}
            id="tab-all"
          >
            <BookOpen size={16} />
            <span>All Saved</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({counts.total})</span>
          </button>

          <button
            role="tab"
            aria-selected={activeTab === 'favorite'}
            onClick={() => setActiveTab('favorite')}
            className={`library-tab-btn ${activeTab === 'favorite' ? 'active' : ''}`}
            id="tab-favorite"
          >
            <Heart size={16} color="#f472b6" fill={activeTab === 'favorite' ? '#f472b6' : 'none'} />
            <span>Favorites</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({counts.favorites})</span>
          </button>

          <button
            role="tab"
            aria-selected={activeTab === 'want_to_read'}
            onClick={() => setActiveTab('want_to_read')}
            className={`library-tab-btn ${activeTab === 'want_to_read' ? 'active' : ''}`}
            id="tab-want-to-read"
          >
            <Bookmark size={16} color="var(--primary)" fill={activeTab === 'want_to_read' ? 'currentColor' : 'none'} />
            <span>Want to Read</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({counts.wantToRead})</span>
          </button>

          <button
            role="tab"
            aria-selected={activeTab === 'finished'}
            onClick={() => setActiveTab('finished')}
            className={`library-tab-btn ${activeTab === 'finished' ? 'active' : ''}`}
            id="tab-finished"
          >
            <CheckCircle size={16} color="var(--success)" />
            <span>Finished</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({counts.finished})</span>
          </button>

          {counts.reading > 0 && (
            <button
              role="tab"
              aria-selected={activeTab === 'reading'}
              onClick={() => setActiveTab('reading')}
              className={`library-tab-btn ${activeTab === 'reading' ? 'active' : ''}`}
              id="tab-reading"
            >
              <BookOpen size={16} color="#fbbf24" />
              <span>Reading</span>
              <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({counts.reading})</span>
            </button>
          )}
        </div>

        {/* Search & Sort Controls */}
        <div style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ position: 'relative', flex: '1', minWidth: '220px' }}>
            <Search
              size={16}
              style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--muted)' }}
            />
            <input
              type="text"
              placeholder="Filter by title or author..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="input-field"
              style={{ width: '100%', paddingLeft: '2.4rem', height: '40px', fontSize: '0.875rem' }}
              aria-label="Filter books by title or author"
            />
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <ArrowUpDown size={16} color="var(--muted)" />
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as SortOption)}
              className="input-field"
              style={{ height: '40px', fontSize: '0.875rem', paddingRight: '2rem', cursor: 'pointer' }}
              aria-label="Sort library books"
            >
              <option value="recent">Recently Added</option>
              <option value="title">Title (A-Z)</option>
              <option value="rating">Highest Rating</option>
            </select>
          </div>
        </div>
      </div>

      {/* Loading Skeletons */}
      {loading && (
        <div className="grid-books">
          {Array.from({ length: 6 }).map((_, idx) => (
            <div
              key={idx}
              className="glass-panel animate-pulse"
              style={{ height: '360px', borderRadius: '16px' }}
            />
          ))}
        </div>
      )}

      {/* Empty State */}
      {!loading && filteredItems.length === 0 && (
        <div
          className="glass-panel text-center animate-fade-in"
          style={{ padding: '4rem 2rem', borderRadius: '16px', margin: '2rem 0' }}
        >
          <div
            style={{
              width: '56px',
              height: '56px',
              borderRadius: '50%',
              background: 'rgba(255, 255, 255, 0.05)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              margin: '0 auto 1.25rem',
            }}
          >
            {activeTab === 'favorite' ? (
              <Heart size={28} color="#f472b6" />
            ) : activeTab === 'want_to_read' ? (
              <Bookmark size={28} color="var(--primary)" />
            ) : (
              <BookOpen size={28} color="var(--muted)" />
            )}
          </div>
          <h2 style={{ fontSize: '1.5rem', marginBottom: '0.5rem' }}>
            {searchQuery
              ? `No books match "${searchQuery}"`
              : activeTab === 'favorite'
              ? 'No favorites saved yet'
              : activeTab === 'want_to_read'
              ? 'Your Want to Read list is empty'
              : activeTab === 'finished'
              ? 'No finished books marked yet'
              : 'Your library is empty'}
          </h2>
          <p className="text-muted" style={{ maxWidth: '440px', margin: '0 auto 2rem', fontSize: '0.95rem' }}>
            {searchQuery
              ? 'Try adjusting your search terms or clearing the filter.'
              : 'Discover captivating reads in our catalog or ask our AI assistant for tailored recommendations.'}
          </p>
          <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'center', flexWrap: 'wrap' }}>
            <Link href="/catalog" className="btn btn-primary">
              <Compass size={16} />
              <span>Explore Catalog</span>
            </Link>
            <Link href="/ai-discovery" className="btn btn-outline">
              <Sparkles size={16} color="var(--accent)" />
              <span>Ask AI Discovery</span>
            </Link>
          </div>
        </div>
      )}

      {/* Books Grid */}
      {!loading && filteredItems.length > 0 && (
        <div className="grid-books">
          {filteredItems.map((item) => {
            const isProcessing = updatingId === item.bookId;
            const book = item.book;
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
              <div
                key={item.id}
                className="glass-panel animate-fade-in"
                style={{
                  padding: '1rem',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: '0.75rem',
                  opacity: isProcessing ? 0.6 : 1,
                  transition: 'opacity 0.2s',
                  position: 'relative',
                }}
              >
                {/* Book Cover Link */}
                <Link
                  href={`/book/${item.bookId}`}
                  style={{ textDecoration: 'none', display: 'block' }}
                >
                  <div className="book-cover-container" style={{ borderRadius: '10px' }}>
                    {!thumbnailUrl ? (
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
                        loading="lazy"
                      />
                    )}

                    {/* Status Badge Over Cover */}
                    <div style={{ position: 'absolute', top: 8, left: 8, zIndex: 2 }}>
                      {item.status === 'favorite' && (
                        <span className="status-badge status-badge-favorite">
                          <Heart size={12} fill="#f472b6" /> Favorite
                        </span>
                      )}
                      {item.status === 'want_to_read' && (
                        <span className="status-badge status-badge-want-to-read">
                          <Bookmark size={12} fill="currentColor" /> Want to Read
                        </span>
                      )}
                      {item.status === 'reading' && (
                        <span className="status-badge status-badge-reading">
                          <BookOpen size={12} /> Reading
                        </span>
                      )}
                      {item.status === 'finished' && (
                        <span className="status-badge status-badge-finished">
                          <CheckCircle size={12} /> Finished
                        </span>
                      )}
                    </div>
                  </div>
                </Link>

                {/* Title & Author */}
                <div style={{ flex: 1 }}>
                  <Link
                    href={`/book/${item.bookId}`}
                    style={{ textDecoration: 'none' }}
                  >
                    <h3 className="book-title" title={book.title}>
                      {book.title}
                    </h3>
                  </Link>
                  <p className="book-author" title={book.authors}>
                    {book.authors || 'Unknown Author'}
                  </p>
                </div>

                {/* Status Switcher & Remove Action */}
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    gap: '0.5rem',
                    borderTop: '1px solid var(--card-border)',
                    paddingTop: '0.75rem',
                    marginTop: 'auto',
                  }}
                >
                  <select
                    value={item.status}
                    disabled={isProcessing}
                    onChange={(e) =>
                      handleStatusChange(item.bookId, e.target.value as LibraryCollectionStatus)
                    }
                    className="input-field"
                    style={{
                      fontSize: '0.8rem',
                      padding: '0.35rem 0.5rem',
                      borderRadius: '6px',
                      flex: 1,
                      cursor: isProcessing ? 'not-allowed' : 'pointer',
                    }}
                    aria-label={`Change collection status for ${book.title}`}
                  >
                    <option value="favorite">Favorite</option>
                    <option value="want_to_read">Want to Read</option>
                    <option value="reading">Reading</option>
                    <option value="finished">Finished</option>
                  </select>

                  <button
                    type="button"
                    onClick={() => handleRemove(item.bookId)}
                    disabled={isProcessing}
                    className="btn btn-outline"
                    style={{
                      padding: '0.4rem',
                      borderRadius: '6px',
                      color: 'var(--danger)',
                      borderColor: 'rgba(239, 68, 68, 0.25)',
                    }}
                    title="Remove from Library"
                    aria-label={`Remove ${book.title} from library`}
                  >
                    <Trash2 size={15} />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </main>
  );
}
