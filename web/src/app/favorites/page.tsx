'use client';

import { useEffect, useState, useTransition, useMemo } from 'react';
import Link from 'next/link';
import { useAuth } from '@/components/AuthProvider';
import { usePreferences } from '@/components/PreferencesProvider';
import {
  getLibraryBooks,
  removeLibraryItem,
  updateLibraryItemStatus,
} from '@/app/actions/library';
import type { LibraryCollectionStatus, LibraryItem, LearningNote, NoteType } from '@/types';
import { getAllUserNotes, deleteNote, updateNote } from '@/app/actions/notes';
import { PenTool } from 'lucide-react';
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
import { ReadingJourneyDashboard } from '@/components/ReadingJourneyDashboard';

type FilterTab = 'all' | LibraryCollectionStatus | 'notes';
type SortOption = 'recent' | 'title' | 'rating';

export default function FavoritesPage() {
  const { user, loading: authLoading } = useAuth();
  const { t } = usePreferences();
  const [items, setItems] = useState<LibraryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<FilterTab>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<SortOption>('recent');
  const [updatingId, setUpdatingId] = useState<string | null>(null);
  const [notes, setNotes] = useState<LearningNote[]>([]);
  const [noteTypeFilter, setNoteTypeFilter] = useState<'all' | NoteType>('all');
  const [editingNoteId, setEditingNoteId] = useState<string | null>(null);
  const [editNoteContent, setEditNoteContent] = useState('');
  const [, startTransition] = useTransition();

  const handleRefresh = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await getLibraryBooks();
      getAllUserNotes().then(nRes => { if (nRes.success) setNotes(nRes.notes); }).catch(() => {});
      if (res.success) {
        setItems(res.items);
      } else {
        setError(res.error || 'Failed to load library items');
      }
    } catch {
      setError(t('library_load_error'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let ignore = false;

    if (!authLoading && user) {
      getAllUserNotes().then(nRes => { if (!ignore && nRes.success) setNotes(nRes.notes); }).catch(() => {});
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
            setError(t('library_load_error'));
            setLoading(false);
          }
        });
    }

    return () => {
      ignore = true;
    };
  }, [user, authLoading, t]);

  // Counts per status
  const counts = useMemo(() => {
    const total = items.length;
    const favorites = items.filter((i) => i.status === 'favorite' || i.isFavorite).length;
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
        if (activeTab === 'favorite') {
          return item.status === 'favorite' || Boolean(item.isFavorite);
        }
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
        setError(t('library_remove_error'));
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
        setError(t('library_status_error'));
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
          <h1 style={{ fontSize: '1.85rem', marginBottom: '0.75rem' }}>{t('unauthenticated_library_title')}</h1>
          <p className="text-muted" style={{ marginBottom: '2rem', fontSize: '0.95rem', lineHeight: '1.6' }}>
            {t('unauthenticated_library_desc')}
          </p>
          <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center' }}>
            <Link href="/login?redirect=/favorites" className="btn btn-primary" id="library-login-btn">
              {t('login_to_libris')}
            </Link>
            <Link href="/signup" className="btn btn-outline">
              {t('create_account')}
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
          <h1 style={{ fontSize: '2.5rem', marginBottom: '0.25rem' }}>{t('library_title')}</h1>
          <p className="text-muted" style={{ fontSize: '1rem' }}>
            {t('library_subtitle')}
          </p>
        </div>
        <button
          onClick={handleRefresh}
          disabled={loading}
          className="btn btn-outline"
          style={{ padding: '0.5rem 1rem', fontSize: '0.85rem' }}
          title={t('refresh')}
          aria-label={t('refresh')}
        >
          <RefreshCw size={15} className={loading ? 'animate-spin' : ''} />
          <span>{t('refresh')}</span>
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
            {t('retry')}
          </button>
        </div>
      )}

      {/* Reading Journey & Progress Dashboard */}
      <ReadingJourneyDashboard items={items} />

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
        <div className="library-tabs" role="tablist" aria-label={t('library_collections')}>
          <button
            role="tab"
            aria-selected={activeTab === 'all'}
            onClick={() => setActiveTab('all')}
            className={`library-tab-btn ${activeTab === 'all' ? 'active' : ''}`}
            id="tab-all"
          >
            <BookOpen size={16} />
            <span>{t('tab_all')}</span>
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
            <span>{t('tab_favorites')}</span>
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
            <span>{t('tab_want_to_read')}</span>
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
            <span>{t('tab_finished')}</span>
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
              <span>{t('tab_reading')}</span>
              <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({counts.reading})</span>
            </button>
          )}

          <button
            role="tab"
            aria-selected={activeTab === 'notes'}
            onClick={() => setActiveTab('notes')}
            className={`library-tab-btn ${activeTab === 'notes' ? 'active' : ''}`}
            id="tab-notes"
          >
            <PenTool size={16} color="var(--accent, #a78bfa)" />
            <span>{t('tab_notes')}</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({notes.length})</span>
          </button>
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
              placeholder={t('search_library_placeholder')}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="input-field"
              style={{ width: '100%', paddingLeft: '2.4rem', height: '40px', fontSize: '0.875rem' }}
              aria-label={t('library_filter_label')}
            />
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <ArrowUpDown size={16} color="var(--muted)" />
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as SortOption)}
              className="input-field"
              style={{ height: '40px', fontSize: '0.875rem', paddingRight: '2rem', cursor: 'pointer' }}
              aria-label={t('library_sort_label')}
            >
              <option value="recent">{t('sort_recent')}</option>
              <option value="title">{t('sort_title')}</option>
              <option value="rating">{t('sort_rating')}</option>
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

      {/* Learning Notes Tab Content */}
      {activeTab === 'notes' && !loading && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          {/* Note Type Filter Bar */}
          <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
            <span style={{ fontSize: '0.85rem', color: 'var(--muted)', marginRight: '0.5rem' }}>
              {t('filters')}:
            </span>
            {(['all', 'personal_note', 'key_takeaway', 'question'] as const).map(ftype => {
              const isSel = noteTypeFilter === ftype;
              const label = ftype === 'all'
                ? t('filter_all_types')
                : ftype === 'key_takeaway'
                ? t('note_type_takeaway')
                : ftype === 'question'
                ? t('note_type_question')
                : t('note_type_personal');
              return (
                <button
                  key={ftype}
                  type="button"
                  onClick={() => setNoteTypeFilter(ftype)}
                  style={{
                    padding: '0.35rem 0.85rem',
                    borderRadius: '9999px',
                    fontSize: '0.825rem',
                    cursor: 'pointer',
                    background: isSel ? 'var(--primary)' : 'rgba(255, 255, 255, 0.05)',
                    border: '1px solid ' + (isSel ? 'var(--primary)' : 'rgba(255, 255, 255, 0.1)'),
                    color: isSel ? '#fff' : 'var(--muted)',
                    fontWeight: isSel ? 600 : 400,
                  }}
                >
                  {label}
                </button>
              );
            })}
          </div>

          {/* Notes List or Empty */}
          {(() => {
            const filteredNotes = notes.filter(n => {
              if (noteTypeFilter !== 'all' && n.noteType !== noteTypeFilter) return false;
              if (searchQuery.trim().length > 0) {
                const q = searchQuery.toLowerCase();
                const matchContent = n.content.toLowerCase().includes(q);
                const matchTitle = n.book?.title?.toLowerCase().includes(q);
                const matchAuthor = n.book?.authors?.toLowerCase().includes(q);
                return matchContent || matchTitle || matchAuthor;
              }
              return true;
            });

            if (filteredNotes.length === 0) {
              return (
                <div
                  className="glass-panel text-center animate-fade-in"
                  style={{ padding: '3.5rem 2rem', borderRadius: '16px' }}
                >
                  <PenTool size={36} color="var(--muted)" style={{ margin: '0 auto 1rem' }} />
                  <h3 style={{ fontSize: '1.35rem', marginBottom: '0.5rem' }}>
                    {searchQuery ? `No notes match "${searchQuery}"` : t('empty_notes_library')}
                  </h3>
                  <p className="text-muted" style={{ maxWidth: '420px', margin: '0 auto', fontSize: '0.9rem' }}>
                    {searchQuery ? 'Try another keyword or change your filter.' : t('notes_subtitle')}
                  </p>
                </div>
              );
            }

            return (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                {filteredNotes.map(n => {
                  const isEditing = editingNoteId === n.id;
                  const typeLabel = n.noteType === 'key_takeaway'
                    ? t('note_type_takeaway')
                    : n.noteType === 'question'
                    ? t('note_type_question')
                    : t('note_type_personal');
                  const badgeColor = n.noteType === 'key_takeaway'
                    ? '#fbbf24'
                    : n.noteType === 'question'
                    ? '#34d399'
                    : 'var(--accent, #a78bfa)';
                  const badgeBg = n.noteType === 'key_takeaway'
                    ? 'rgba(245, 158, 11, 0.15)'
                    : n.noteType === 'question'
                    ? 'rgba(16, 185, 129, 0.15)'
                    : 'rgba(139, 92, 246, 0.15)';

                  return (
                    <article
                      key={n.id}
                      className="glass-panel animate-fade-in"
                      style={{ padding: '1.25rem 1.5rem', borderRadius: '12px' }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem', flexWrap: 'wrap', gap: '0.5rem' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                          <span
                            style={{
                              padding: '0.2rem 0.65rem',
                              borderRadius: '9999px',
                              fontSize: '0.75rem',
                              fontWeight: 600,
                              background: badgeBg,
                              color: badgeColor,
                            }}
                          >
                            {typeLabel}
                          </span>
                          {n.bookId && (
                            <Link
                              href={`/book/${encodeURIComponent(n.bookId)}`}
                              style={{ fontSize: '0.875rem', fontWeight: 600, color: 'var(--primary)', textDecoration: 'none' }}
                            >
                              {n.book?.title || `Book: ${n.bookId}`}
                            </Link>
                          )}
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                          <span style={{ fontSize: '0.75rem', color: 'var(--muted)' }}>
                            {new Date(n.createdAt).toLocaleDateString()}
                          </span>
                          <button
                            type="button"
                            onClick={() => {
                              setEditingNoteId(n.id);
                              setEditNoteContent(n.content);
                            }}
                            className="btn btn-outline"
                            style={{ padding: '0.25rem 0.6rem', fontSize: '0.75rem' }}
                          >
                            {t('edit_note')}
                          </button>
                          <button
                            type="button"
                            onClick={async () => {
                              const prev = [...notes];
                              setNotes(prev.filter(x => x.id !== n.id));
                              const res = await deleteNote(n.id, n.bookId);
                              if (!res.success) setNotes(prev);
                            }}
                            className="btn"
                            style={{ padding: '0.25rem 0.6rem', fontSize: '0.75rem', background: 'rgba(239, 68, 68, 0.15)', color: 'var(--danger)' }}
                          >
                            {t('delete_note')}
                          </button>
                        </div>
                      </div>

                      {isEditing ? (
                        <div style={{ marginTop: '0.5rem' }}>
                          <textarea
                            value={editNoteContent}
                            onChange={(e) => setEditNoteContent(e.target.value)}
                            rows={3}
                            style={{
                              width: '100%',
                              padding: '0.6rem',
                              borderRadius: '8px',
                              background: 'rgba(0,0,0,0.3)',
                              color: '#fff',
                              border: '1px solid rgba(255,255,255,0.15)',
                              outline: 'none',
                              fontSize: '0.9rem',
                            }}
                          />
                          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.5rem', marginTop: '0.5rem' }}>
                            <button
                              type="button"
                              onClick={() => setEditingNoteId(null)}
                              className="btn"
                              style={{ padding: '0.3rem 0.75rem', fontSize: '0.8rem', background: 'rgba(255,255,255,0.08)' }}
                            >
                              {t('cancel')}
                            </button>
                            <button
                              type="button"
                              onClick={async () => {
                                const prev = [...notes];
                                setNotes(prev.map(x => x.id === n.id ? { ...x, content: editNoteContent } : x));
                                setEditingNoteId(null);
                                const res = await updateNote(n.id, editNoteContent, n.noteType);
                                if (!res.success) setNotes(prev);
                              }}
                              className="btn btn-primary"
                              style={{ padding: '0.3rem 0.75rem', fontSize: '0.8rem' }}
                            >
                              {t('save_note')}
                            </button>
                          </div>
                        </div>
                      ) : (
                        <p style={{ margin: 0, fontSize: '0.95rem', lineHeight: 1.6, color: 'rgba(255,255,255,0.88)', whiteSpace: 'pre-wrap' }}>
                          {n.content}
                        </p>
                      )}
                    </article>
                  );
                })}
              </div>
            );
          })()}
        </div>
      )}


      {/* Empty State for Book Shelves */}
      {!loading && activeTab !== 'notes' && filteredItems.length === 0 && (
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
              : t('empty_library_title')}
          </h2>
          <p className="text-muted" style={{ maxWidth: '440px', margin: '0 auto 2rem', fontSize: '0.95rem' }}>
            {searchQuery
              ? 'Try adjusting your search terms or clearing the filter.'
              : t('empty_library_desc')}
          </p>
          <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'center', flexWrap: 'wrap' }}>
            <Link href="/catalog" className="btn btn-primary">
              <Compass size={16} />
              <span>{t('explore_catalog_cta')}</span>
            </Link>
            <Link href="/ai-discovery" className="btn btn-outline">
              <Sparkles size={16} color="var(--accent)" />
              <span>{t('ai_discovery_cta')}</span>
            </Link>
          </div>
        </div>
      )}

      {/* Books Grid */}
      {!loading && activeTab !== 'notes' && filteredItems.length > 0 && (
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
                          <Heart size={12} fill="#f472b6" /> {t('status_favorite')}
                        </span>
                      )}
                      {item.status === 'want_to_read' && (
                        <span className="status-badge status-badge-want-to-read">
                          <Bookmark size={12} fill="currentColor" /> {t('status_want_to_read')}
                        </span>
                      )}
                      {item.status === 'reading' && (
                        <span className="status-badge status-badge-reading">
                          <BookOpen size={12} /> {t('status_reading')}
                        </span>
                      )}
                      {item.status === 'finished' && (
                        <span className="status-badge status-badge-finished">
                          <CheckCircle size={12} /> {t('status_finished')}
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
                    <option value="favorite">{t('status_favorite')}</option>
                    <option value="want_to_read">{t('status_want_to_read')}</option>
                    <option value="reading">{t('status_reading')}</option>
                    <option value="finished">{t('status_finished')}</option>
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
                    title={t('remove_from_library')}
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
