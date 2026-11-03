'use client';

import React, { useState, useEffect, useTransition } from 'react';
import Link from 'next/link';
import type { LearningPath, Book, LibraryCollectionStatus } from '@/types';
import { usePreferences } from '@/components/PreferencesProvider';
import { useAuth } from '@/components/AuthProvider';
import {
  getLearningPathsAction,
  getLearningPathDetailAction,
  createLearningPathAction,
  deleteLearningPathAction,
  addBookToLearningPathAction,
  removeBookFromLearningPathAction,
  reorderLearningPathBooksAction,
  getLearningPathSuggestionsAction,
  getLearningPathRecommendationsAction,
} from '@/app/actions/learning_paths';
import { updateBookStatusAction } from '@/app/actions/library';
import {
  Compass,
  Plus,
  Trash2,
  CheckCircle2,
  ArrowUp,
  ArrowDown,
  Sparkles,
  X,
  AlertCircle,
  Play,
  Brain,
} from 'lucide-react';
import { BookCoverFallback } from './BookCoverFallback';

export interface LearningPathsDashboardProps {
  className?: string;
}

export function LearningPathsDashboard({ className = '' }: LearningPathsDashboardProps) {
  const { t } = usePreferences();
  const { user, loading: authLoading } = useAuth();
  const [paths, setPaths] = useState<LearningPath[]>([]);
  const [activePathId, setActivePathId] = useState<string | null>(null);
  const [activePath, setActivePath] = useState<LearningPath | null>(null);
  const [loading, setLoading] = useState(false);
  // loading detail removed
  const [error, setError] = useState<string | null>(null);

  // Create Modal State
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [newTitle, setNewTitle] = useState('');
  const [newCategory, setNewCategory] = useState('');
  const [newDescription, setNewDescription] = useState('');
  const [submitting, setSubmitting] = useState(false);

  // Suggestions / Add Book State
  const [suggestions, setSuggestions] = useState<Book[]>([]);
  // loading suggestions removed
  const [, startTransition] = useTransition();

  // Load paths on mount or auth change
  useEffect(() => {
    let ignore = false;
    if (user && !authLoading) {
      startTransition(() => {
        setLoading(true);
      });
      getLearningPathsAction()
        .then((res) => {
          if (!ignore && res.success) {
            setPaths(res.paths);
            if (res.paths.length > 0) {
              setActivePathId((prev) => (prev && res.paths.some((p) => p.id === prev) ? prev : res.paths[0].id));
            }
          }
        })
        .catch(() => {
          if (!ignore) setError('Failed to load learning paths');
        })
        .finally(() => {
          if (!ignore) setLoading(false);
        });
    } else {
      startTransition(() => {
        setPaths([]);
        setActivePath(null);
      });
    }
    return () => {
      ignore = true;
    };
  }, [user, authLoading]);

  // Load active path details
  useEffect(() => {
    let ignore = false;
    if (activePathId && user) {

      getLearningPathDetailAction(activePathId)
        .then((res) => {
          if (!ignore && res.success && res.path) {
            setActivePath(res.path);
            // Fetch adaptive personalized candidates for this learning path
            
            getLearningPathRecommendationsAction(res.path.id, 8, true)
              .then((rRes) => {
                if (!ignore && rRes.success && rRes.recommendations.length > 0) {
                  setSuggestions(rRes.recommendations);
                } else if (!ignore && res.path?.category) {
                  getLearningPathSuggestionsAction(res.path.category)
                    .then((sRes) => {
                      if (!ignore && sRes.success) {
                        setSuggestions(sRes.suggestions);
                      }
                    });
                } else if (!ignore) {
                  setSuggestions([]);
                }
              })
              .catch(() => {
                if (!ignore && res.path?.category) {
                  getLearningPathSuggestionsAction(res.path.category).then((sRes) => {
                    if (!ignore && sRes.success) setSuggestions(sRes.suggestions);
                  });
                }
              })

          }
        })
        .catch(() => {
          if (!ignore) setError('Failed to load path detail');
        })

    } else {
      startTransition(() => {
        setActivePath(null);
      });
    }
    return () => {
      ignore = true;
    };
  }, [activePathId, user]);

  const handleCreatePath = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTitle.trim()) return;

    setSubmitting(true);
    setError(null);
    try {
      const res = await createLearningPathAction({
        title: newTitle.trim(),
        category: newCategory.trim() || undefined,
        description: newDescription.trim() || undefined,
      });

      if (res.success && res.path) {
        setPaths((prev) => [res.path!, ...prev]);
        setActivePathId(res.path.id);
        setIsCreateModalOpen(false);
        setNewTitle('');
        setNewCategory('');
        setNewDescription('');
      } else {
        setError(res.error || 'Failed to create path');
      }
    } catch {
      setError('A network error occurred');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeletePath = async (pathId: string) => {
    if (!confirm(t('path_confirm_delete'))) return;

    const previousPaths = [...paths];
    setPaths((prev) => prev.filter((p) => p.id !== pathId));
    if (activePathId === pathId) {
      const remaining = paths.filter((p) => p.id !== pathId);
      setActivePathId(remaining.length > 0 ? remaining[0].id : null);
    }

    try {
      const res = await deleteLearningPathAction(pathId);
      if (!res.success) {
        setPaths(previousPaths);
        setError(res.error || 'Failed to delete path');
      }
    } catch {
      setPaths(previousPaths);
      setError('A network error occurred');
    }
  };

  const handleAddBook = async (bookId: string) => {
    if (!activePathId) return;
    try {
      const res = await addBookToLearningPathAction(activePathId, bookId);
      if (res.success && res.path) {
        setActivePath(res.path);
        // Refresh paths list summary
        setPaths((prev) => prev.map((p) => (p.id === activePathId ? { ...p, totalBooks: (p.totalBooks || 0) + 1 } : p)));
      }
    } catch {
      setError('Failed to add book to path');
    }
  };

  const handleRemoveBook = async (bookId: string) => {
    if (!activePathId) return;
    try {
      const res = await removeBookFromLearningPathAction(activePathId, bookId);
      if (res.success && res.path) {
        setActivePath(res.path);
        setPaths((prev) => prev.map((p) => (p.id === activePathId ? { ...p, totalBooks: Math.max(0, (p.totalBooks || 1) - 1) } : p)));
      }
    } catch {
      setError('Failed to remove book from path');
    }
  };

  const handleMoveBook = async (index: number, direction: 'up' | 'down') => {
    if (!activePath || !activePath.books) return;
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= activePath.books.length) return;

    const newBooks = [...activePath.books];
    const temp = newBooks[index];
    newBooks[index] = newBooks[targetIndex];
    newBooks[targetIndex] = temp;

    const bookIds = newBooks.map((b) => b.bookId);

    // Optimistic UI update
    setActivePath({ ...activePath, books: newBooks });

    try {
      await reorderLearningPathBooksAction(activePath.id, bookIds);
    } catch {
      setError('Failed to reorder books');
    }
  };

  const handleUpdateBookReadingStatus = async (bookId: string, status: LibraryCollectionStatus) => {
    try {
      await updateBookStatusAction(bookId, status);
      // Reload path detail to get fresh metrics
      if (activePathId) {
        const res = await getLearningPathDetailAction(activePathId);
        if (res.success && res.path) {
          setActivePath(res.path);
        }
      }
    } catch {
      setError('Failed to update book reading status');
    }
  };

  if (!user && !authLoading) {
    return null;
  }

  return (
    <section
      aria-label={t('learning_paths_title')}
      className={`glass-panel learning-paths-dashboard animate-fade-in ${className}`}
      style={{
        borderRadius: '20px',
        padding: '1.75rem',
        marginBottom: '2rem',
        background: 'linear-gradient(135deg, var(--surface) 0%, var(--surface-subtle) 100%)',
        border: '1px solid var(--card-border)',
      }}
    >
      {/* ── Top Header ──────────────────────────────────────────────────── */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexWrap: 'wrap',
          gap: '1rem',
          marginBottom: '1.5rem',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
          <div
            style={{
              width: '42px',
              height: '42px',
              borderRadius: '12px',
              background: 'linear-gradient(135deg, var(--accent), var(--primary))',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#ffffff',
              boxShadow: '0 4px 12px rgba(139, 92, 246, 0.25)',
            }}
          >
            <Compass size={22} />
          </div>
          <div>
            <h2 style={{ fontSize: '1.3rem', fontWeight: 700, margin: 0, lineHeight: 1.2 }}>
              {t('learning_paths_title')}
            </h2>
            <p className="text-muted" style={{ fontSize: '0.85rem', margin: '3px 0 0' }}>
              {t('learning_paths_subtitle')}
            </p>
          </div>
        </div>

        <button
          type="button"
          onClick={() => setIsCreateModalOpen(true)}
          className="btn btn-primary"
          style={{ padding: '0.45rem 1rem', fontSize: '0.85rem', gap: '0.4rem' }}
          aria-label={t('create_path')}
        >
          <Plus size={16} />
          <span>{t('create_path')}</span>
        </button>
      </div>

      {error && (
        <div
          role="alert"
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            padding: '0.75rem 1rem',
            borderRadius: '10px',
            background: 'rgba(239, 68, 68, 0.12)',
            color: 'var(--danger, #ef4444)',
            marginBottom: '1.25rem',
            fontSize: '0.85rem',
          }}
        >
          <AlertCircle size={16} />
          <span>{error}</span>
          <button
            type="button"
            onClick={() => setError(null)}
            style={{ marginLeft: 'auto', background: 'none', border: 'none', color: 'inherit', cursor: 'pointer' }}
          >
            <X size={14} />
          </button>
        </div>
      )}

      {/* ── Empty State ─────────────────────────────────────────────────── */}
      {paths.length === 0 && !loading && (
        <div
          style={{
            textAlign: 'center',
            padding: '3rem 1.5rem',
            borderRadius: '14px',
            background: 'var(--surface-elevated)',
            border: '1px dashed var(--card-border)',
          }}
        >
          <Compass size={40} style={{ margin: '0 auto 1rem', color: 'var(--muted)', opacity: 0.6 }} />
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600, margin: '0 0 0.5rem' }}>
            {t('path_empty_title')}
          </h3>
          <p className="text-muted" style={{ fontSize: '0.85rem', maxWidth: '420px', margin: '0 auto 1.5rem' }}>
            {t('path_empty_desc')}
          </p>
          <button
            type="button"
            onClick={() => setIsCreateModalOpen(true)}
            className="btn btn-primary"
            style={{ padding: '0.5rem 1.25rem', fontSize: '0.85rem' }}
          >
            <Plus size={16} style={{ marginRight: '6px' }} />
            <span>{t('create_path')}</span>
          </button>
        </div>
      )}

      {/* ── Path Tabs / Selector ────────────────────────────────────────── */}
      {paths.length > 0 && (
        <div
          style={{
            display: 'flex',
            gap: '0.65rem',
            overflowX: 'auto',
            paddingBottom: '0.5rem',
            marginBottom: '1.5rem',
          }}
        >
          {paths.map((p) => {
            const isSelected = p.id === activePathId;
            return (
              <button
                key={p.id}
                type="button"
                onClick={() => setActivePathId(p.id)}
                style={{
                  padding: '0.5rem 1rem',
                  borderRadius: '10px',
                  border: isSelected ? '1px solid var(--primary)' : '1px solid var(--card-border)',
                  background: isSelected ? 'rgba(99, 102, 241, 0.12)' : 'var(--surface-elevated)',
                  color: isSelected ? 'var(--primary)' : 'var(--foreground)',
                  fontWeight: isSelected ? 700 : 500,
                  fontSize: '0.85rem',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '0.5rem',
                  whiteSpace: 'nowrap',
                  flexShrink: 0,
                  transition: 'all 0.2s ease',
                }}
              >
                <span>{p.title}</span>
                {p.category && (
                  <span
                    style={{
                      fontSize: '0.72rem',
                      opacity: 0.8,
                      background: 'rgba(255, 255, 255, 0.08)',
                      padding: '2px 6px',
                      borderRadius: '4px',
                    }}
                  >
                    {p.category}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      )}

      {/* ── Active Path Detail Card & Books ──────────────────────────────── */}
      {activePath && (
        <div
          style={{
            background: 'var(--surface-elevated)',
            borderRadius: '16px',
            padding: '1.5rem',
            border: '1px solid var(--card-border)',
          }}
        >
          {/* Path Header & Actions */}
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'flex-start',
              flexWrap: 'wrap',
              gap: '1rem',
              marginBottom: '1.25rem',
            }}
          >
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', flexWrap: 'wrap' }}>
                <h3 style={{ fontSize: '1.2rem', fontWeight: 700, margin: 0 }}>
                  {activePath.title}
                </h3>
                {activePath.status === 'completed' && (
                  <span
                    style={{
                      fontSize: '0.75rem',
                      fontWeight: 700,
                      padding: '2px 8px',
                      borderRadius: '9999px',
                      background: 'rgba(16, 185, 129, 0.15)',
                      color: 'var(--success, #10b981)',
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '4px',
                    }}
                  >
                    <CheckCircle2 size={12} /> {t('path_all_completed')}
                  </span>
                )}
              </div>
              {activePath.description && (
                <p className="text-muted" style={{ fontSize: '0.85rem', margin: '4px 0 0' }}>
                  {activePath.description}
                </p>
              )}
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <Link
                href={`/learning?path_id=${encodeURIComponent(activePath.id)}`}
                className="btn btn-outline"
                style={{
                  padding: '0.35rem 0.75rem',
                  fontSize: '0.75rem',
                  color: 'var(--primary)',
                  borderColor: 'var(--primary)',
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: '4px',
                  textDecoration: 'none',
                }}
                title={t('start_path_reviews')}
              >
                <Brain size={13} />
                <span>{t('start_path_reviews')}</span>
              </Link>
              <button
                type="button"
                onClick={() => handleDeletePath(activePath.id)}
                className="btn btn-outline"
                style={{
                  padding: '0.35rem 0.65rem',
                  fontSize: '0.75rem',
                  color: 'var(--danger, #ef4444)',
                  borderColor: 'rgba(239, 68, 68, 0.3)',
                }}
                title={t('delete_path')}
              >
                <Trash2 size={13} style={{ marginRight: '4px' }} />
                <span>{t('delete_path')}</span>
              </button>
            </div>
          </div>

          {/* Progress Intelligence Bar */}
          <div
            style={{
              background: 'var(--surface-subtle)',
              padding: '1rem',
              borderRadius: '12px',
              marginBottom: '1.5rem',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem', fontSize: '0.85rem' }}>
              <span style={{ fontWeight: 600 }}>
                {t('path_progress_label')}:{' '}
                <strong style={{ color: 'var(--foreground)' }}>{activePath.completedBooks || 0}</strong> /{' '}
                <strong style={{ color: 'var(--primary)' }}>{activePath.totalBooks || 0}</strong> {t('path_books_count', { count: '' })}
              </span>
              <span style={{ fontWeight: 700, color: 'var(--primary)' }}>
                {activePath.progressPercent || 0}%
              </span>
            </div>
            <div
              style={{
                width: '100%',
                height: '8px',
                borderRadius: '9999px',
                background: 'rgba(255, 255, 255, 0.1)',
                overflow: 'hidden',
              }}
            >
              <div
                style={{
                  width: `${activePath.progressPercent || 0}%`,
                  height: '100%',
                  borderRadius: '9999px',
                  background: 'linear-gradient(90deg, var(--primary), var(--accent))',
                  transition: 'width 0.4s ease',
                }}
              />
            </div>
          </div>

          {/* Ordered Books Sequence */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', marginBottom: '1.75rem' }}>
            {activePath.books && activePath.books.length > 0 ? (
              activePath.books.map((item, index) => {
                const book = item.book;
                const isNext = item.bookId === activePath.nextBookId;
                const isFinished = item.readingStatus === 'finished';
                const isReading = item.readingStatus === 'reading';

                return (
                  <div
                    key={item.bookId}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: '1rem',
                      padding: '0.85rem 1rem',
                      borderRadius: '12px',
                      background: isNext ? 'rgba(99, 102, 241, 0.08)' : 'var(--surface-subtle)',
                      border: isNext ? '1px solid var(--primary)' : '1px solid var(--card-border)',
                      flexWrap: 'wrap',
                    }}
                  >
                    {/* Index Sequence Number */}
                    <div
                      style={{
                        width: '28px',
                        height: '28px',
                        borderRadius: '50%',
                        background: isFinished ? 'rgba(16, 185, 129, 0.2)' : 'rgba(255, 255, 255, 0.08)',
                        color: isFinished ? 'var(--success, #10b981)' : 'var(--text-muted)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        fontWeight: 700,
                        fontSize: '0.8rem',
                        flexShrink: 0,
                      }}
                    >
                      {isFinished ? <CheckCircle2 size={15} /> : index + 1}
                    </div>

                    {/* Book Thumbnail */}
                    <div
                      style={{
                        width: '40px',
                        height: '60px',
                        borderRadius: '6px',
                        overflow: 'hidden',
                        flexShrink: 0,
                        position: 'relative',
                      }}
                    >
                      {book?.thumbnail && book.thumbnail !== 'None' ? (
                        /* eslint-disable-next-line @next/next/no-img-element */
                        <img
                          src={book.thumbnail.replace('http:', 'https:')}
                          alt={book.title || 'Book cover'}
                          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                          loading="lazy"
                        />
                      ) : (
                        <BookCoverFallback
                          title={book?.title || 'Book'}
                          authors={book?.authors || ''}
                          style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%' }}
                        />
                      )}
                    </div>

                    {/* Book Metadata */}
                    <div style={{ flex: 1, minWidth: '180px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                        <Link
                          href={`/book/${item.bookId}`}
                          style={{ textDecoration: 'none', color: 'inherit', fontWeight: 600, fontSize: '0.92rem' }}
                        >
                          {book?.title || `Book ${item.bookId}`}
                        </Link>
                        {isNext && (
                          <span
                            style={{
                              fontSize: '0.68rem',
                              fontWeight: 700,
                              padding: '1px 6px',
                              borderRadius: '4px',
                              background: 'var(--primary)',
                              color: '#ffffff',
                            }}
                          >
                            {t('path_next_book')}
                          </span>
                        )}
                      </div>
                      <p className="text-muted" style={{ fontSize: '0.78rem', margin: '2px 0 0' }}>
                        {book?.authors || 'Unknown Author'}
                      </p>
                    </div>

                    {/* 1-Tap Reading Status Actions */}
                    <div style={{ display: 'flex', gap: '0.4rem', alignItems: 'center' }}>
                      {!isReading && !isFinished && (
                        <button
                          type="button"
                          onClick={() => handleUpdateBookReadingStatus(item.bookId, 'reading')}
                          className="btn btn-outline"
                          style={{ padding: '0.3rem 0.65rem', fontSize: '0.75rem', gap: '0.3rem' }}
                          title="Start reading"
                        >
                          <Play size={12} fill="currentColor" />
                          <span>Start Reading</span>
                        </button>
                      )}

                      {isReading && (
                        <button
                          type="button"
                          onClick={() => handleUpdateBookReadingStatus(item.bookId, 'finished')}
                          className="btn btn-primary"
                          style={{ padding: '0.3rem 0.65rem', fontSize: '0.75rem', gap: '0.3rem' }}
                          title="Mark finished"
                        >
                          <CheckCircle2 size={12} />
                          <span>Complete</span>
                        </button>
                      )}

                      {isFinished && (
                        <span
                          style={{
                            fontSize: '0.75rem',
                            fontWeight: 600,
                            color: 'var(--success, #10b981)',
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '4px',
                            padding: '0.2rem 0.5rem',
                          }}
                        >
                          <CheckCircle2 size={13} /> Completed
                        </span>
                      )}

                      {/* Reorder Controls */}
                      <button
                        type="button"
                        onClick={() => handleMoveBook(index, 'up')}
                        disabled={index === 0}
                        className="btn btn-outline"
                        style={{ padding: '0.25rem 0.45rem', fontSize: '0.7rem' }}
                        title={t('move_up')}
                        aria-label={t('move_up')}
                      >
                        <ArrowUp size={12} />
                      </button>

                      <button
                        type="button"
                        onClick={() => handleMoveBook(index, 'down')}
                        disabled={index === activePath.books.length - 1}
                        className="btn btn-outline"
                        style={{ padding: '0.25rem 0.45rem', fontSize: '0.7rem' }}
                        title={t('move_down')}
                        aria-label={t('move_down')}
                      >
                        <ArrowDown size={12} />
                      </button>

                      {/* Remove Button */}
                      <button
                        type="button"
                        onClick={() => handleRemoveBook(item.bookId)}
                        className="btn btn-outline"
                        style={{ padding: '0.25rem 0.45rem', fontSize: '0.7rem', color: 'var(--muted)' }}
                        title={t('remove_from_path')}
                        aria-label={t('remove_from_path')}
                      >
                        <Trash2 size={12} />
                      </button>
                    </div>
                  </div>
                );
              })
            ) : (
              <p className="text-muted" style={{ fontSize: '0.85rem', textAlign: 'center', padding: '1rem' }}>
                No books added to this path yet. Select from suggestions below or search the catalog.
              </p>
            )}
          </div>

          {/* ── Suggested Books to Add ─────────────────────────────────────── */}
          {suggestions.length > 0 && (
            <div style={{ borderTop: '1px solid var(--card-border)', paddingTop: '1.25rem' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', marginBottom: '0.75rem' }}>
                <Sparkles size={16} color="var(--primary)" />
                <h4 style={{ fontSize: '0.95rem', fontWeight: 700, margin: 0 }}>
                  {t('suggested_books')} ({activePath.category || 'Topic'})
                </h4>
              </div>

              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
                  gap: '0.75rem',
                }}
              >
                {suggestions.map((sBook) => {
                  const alreadyInPath = activePath.books?.some((b) => b.bookId === sBook.isbn13);
                  if (alreadyInPath) return null;

                  return (
                    <div
                      key={sBook.isbn13}
                      style={{
                        padding: '0.65rem 0.75rem',
                        borderRadius: '10px',
                        background: 'var(--surface-subtle)',
                        border: '1px solid var(--card-border)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        gap: '0.5rem',
                      }}
                    >
                      <div style={{ minWidth: 0, flex: 1 }}>
                        <div
                          style={{
                            fontWeight: 600,
                            fontSize: '0.82rem',
                            whiteSpace: 'nowrap',
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                          }}
                          title={sBook.title}
                        >
                          {sBook.title}
                        </div>
                        <div
                          className="text-muted"
                          style={{
                            fontSize: '0.72rem',
                            whiteSpace: 'nowrap',
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                          }}
                        >
                          {sBook.authors}
                        </div>
                      </div>

                      <button
                        type="button"
                        onClick={() => handleAddBook(sBook.isbn13)}
                        className="btn btn-outline"
                        style={{ padding: '0.25rem 0.6rem', fontSize: '0.72rem', gap: '3px' }}
                        title={t('add_to_path')}
                      >
                        <Plus size={11} />
                        <span>Add</span>
                      </button>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>
      )}

      {/* ── Create Path Modal ────────────────────────────────────────────── */}
      {isCreateModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            background: 'rgba(0, 0, 0, 0.7)',
            backdropFilter: 'blur(4px)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '1rem',
            zIndex: 9999,
          }}
          onClick={(e) => {
            if (e.target === e.currentTarget) setIsCreateModalOpen(false);
          }}
        >
          <div
            style={{
              background: 'var(--surface-elevated, #18181b)',
              border: '1px solid var(--card-border)',
              borderRadius: '16px',
              width: '100%',
              maxWidth: '460px',
              padding: '1.75rem',
              boxShadow: '0 20px 40px rgba(0, 0, 0, 0.5)',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <Compass size={20} color="var(--primary)" />
                <h3 style={{ fontSize: '1.15rem', fontWeight: 700, margin: 0 }}>{t('create_path')}</h3>
              </div>
              <button
                type="button"
                onClick={() => setIsCreateModalOpen(false)}
                style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer' }}
                aria-label="Close"
              >
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleCreatePath}>
              <div style={{ marginBottom: '1rem' }}>
                <label style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: '0.4rem' }}>
                  {t('path_title_label')} *
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Stoicism & Practical Wisdom"
                  value={newTitle}
                  onChange={(e) => setNewTitle(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '0.55rem 0.85rem',
                    borderRadius: '8px',
                    background: 'var(--surface-subtle)',
                    border: '1px solid var(--card-border)',
                    color: 'var(--foreground)',
                    fontSize: '0.9rem',
                  }}
                  autoFocus
                />
              </div>

              <div style={{ marginBottom: '1rem' }}>
                <label style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: '0.4rem' }}>
                  {t('path_category_label')}
                </label>
                <input
                  type="text"
                  placeholder="e.g. Philosophy, Science, Fiction"
                  value={newCategory}
                  onChange={(e) => setNewCategory(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '0.55rem 0.85rem',
                    borderRadius: '8px',
                    background: 'var(--surface-subtle)',
                    border: '1px solid var(--card-border)',
                    color: 'var(--foreground)',
                    fontSize: '0.9rem',
                  }}
                />
              </div>

              <div style={{ marginBottom: '1.5rem' }}>
                <label style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: '0.4rem' }}>
                  {t('path_desc_label')}
                </label>
                <textarea
                  rows={3}
                  placeholder="Goals and focus areas for this learning path..."
                  value={newDescription}
                  onChange={(e) => setNewDescription(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '0.55rem 0.85rem',
                    borderRadius: '8px',
                    background: 'var(--surface-subtle)',
                    border: '1px solid var(--card-border)',
                    color: 'var(--foreground)',
                    fontSize: '0.9rem',
                    resize: 'none',
                  }}
                />
              </div>

              <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end' }}>
                <button
                  type="button"
                  onClick={() => setIsCreateModalOpen(false)}
                  className="btn btn-outline"
                  style={{ padding: '0.45rem 1rem', fontSize: '0.85rem' }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting || !newTitle.trim()}
                  className="btn btn-primary"
                  style={{ padding: '0.45rem 1.25rem', fontSize: '0.85rem' }}
                >
                  {submitting ? 'Creating...' : t('create_path')}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </section>
  );
}

