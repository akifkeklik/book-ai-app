'use client';

import { useState, useEffect, useMemo, useCallback } from 'react';
import Link from 'next/link';
import { useAuth } from './AuthProvider';
import { usePreferences } from './PreferencesProvider';
import type { TranslationKey } from '@/lib/i18n';
import {
  getPersonalizedRecommendationsAction,
  dismissRecommendationAction,
  resetPersonalizationAction,
} from '@/app/actions/discovery';
import {
  getLibraryBooks,
  addFavoriteItem,
  removeFavoriteItem,
  updateLibraryItemStatus,
  removeLibraryItem,
} from '@/app/actions/library';
import { getUserPreferencesAction } from '@/app/actions/user';
import { PersonalizedDiscoveryCard } from './PersonalizedDiscoveryCard';
import {
  classifyRecommendation,
  filterRecommendations,
  type DiscoveryFilterType,
} from '@/lib/discovery';
import type { Book, LibraryCollectionStatus } from '@/types';
import {
  Sparkles,
  RefreshCw,
  AlertCircle,
  Lock,
  Search,
  Compass,
  CheckCircle2,
  SlidersHorizontal,
  Bookmark,
  Heart,
  BookOpen,
  RotateCcw,
  EyeOff,
} from 'lucide-react';
import { TasteProfileModal } from './TasteProfileModal';
import { ReadingJourneyDashboard } from './ReadingJourneyDashboard';
import { determineNextBook } from '@/lib/reading_journey';
import type { LibraryItem } from '@/types';
import { translateGenre } from '@/lib/i18n';

const DEFAULT_CATEGORIES = [
  'Fiction',
  'Science',
  'History',
  'Philosophy',
  'Mystery',
  'Fantasy',
  'Psychology',
  'Biography',
  'Romance',
];

export function PersonalizedDiscoveryView() {
  const { user, loading: authLoading } = useAuth();
  const { t, preferences } = usePreferences();

  const [books, setBooks] = useState<Book[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [isSessionExpired, setIsSessionExpired] = useState<boolean>(false);
  const [isColdStart, setIsColdStart] = useState<boolean>(false);
  const [evidenceCoverage, setEvidenceCoverage] = useState<'cold_start' | 'emerging' | 'established' | null>(null);
  const [excludeCompleted, setExcludeCompleted] = useState<boolean>(false);

  // Filters & Search
  const [activeFilter, setActiveFilter] = useState<DiscoveryFilterType>('all');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [preferredGenres, setPreferredGenres] = useState<string[]>([]);
  const [modalOpen, setModalOpen] = useState<boolean>(false);

  // In-flight mutations & library statuses
  const [libraryItems, setLibraryItems] = useState<LibraryItem[]>([]);
  const [libraryMap, setLibraryMap] = useState<
    Map<string, { isFavorite: boolean; status: LibraryCollectionStatus | null }>
  >(new Map());
  const [pendingDismissals, setPendingDismissals] = useState<Set<string>>(new Set());
  const [pendingMutations, setPendingMutations] = useState<Set<string>>(new Set());

  // Load recommendations and library collections
  const loadData = useCallback(
    async (categoryOverride?: string, excludeCompletedOverride?: boolean) => {
      setLoading(true);
      setError(null);
      setIsSessionExpired(false);

      const targetCategory =
        categoryOverride !== undefined ? categoryOverride : selectedCategory;
      const catParam = targetCategory !== 'all' ? targetCategory : undefined;
      const targetExclude =
        excludeCompletedOverride !== undefined ? excludeCompletedOverride : excludeCompleted;

      try {
        const [recsRes, libraryRes, prefsRes] = await Promise.all([
          getPersonalizedRecommendationsAction(30, catParam, targetExclude),
          getLibraryBooks().catch(() => ({ success: false, items: [] })),
          getUserPreferencesAction().catch(() => ({
            success: false,
            preferredGenres: [],
            preferredAuthors: [],
          })),
        ]);

        if (!recsRes.isAuthenticated) {
          setIsSessionExpired(true);
          setLoading(false);
          return;
        }

        if (recsRes.success) {
          setBooks(recsRes.books || []);
          setIsColdStart(Boolean(recsRes.isColdStart));
          setEvidenceCoverage(recsRes.evidenceCoverage || null);
        } else {
          setError(recsRes.error || 'Failed to load recommendations');
        }

        if (libraryRes?.success && Array.isArray(libraryRes.items)) {
          setLibraryItems(libraryRes.items);
          const map = new Map<
            string,
            { isFavorite: boolean; status: LibraryCollectionStatus | null }
          >();
          for (const item of libraryRes.items) {
            map.set(item.bookId, {
              isFavorite: Boolean(item.isFavorite || item.status === 'favorite'),
              status: item.status,
            });
          }
          setLibraryMap(map);
        }

        if (prefsRes?.success && Array.isArray(prefsRes.preferredGenres)) {
          setPreferredGenres(prefsRes.preferredGenres);
        }
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : 'Network error';
        if (msg.toLowerCase().includes('unauthorized') || msg.includes('401')) {
          setIsSessionExpired(true);
        } else {
          setError(msg);
        }
      } finally {
        setLoading(false);
      }
    },
    [selectedCategory, excludeCompleted]
  );

  const isUnauthenticated = !authLoading && !user;
  const showSessionExpired = isSessionExpired || isUnauthenticated;

  useEffect(() => {
    let ignore = false;
    if (!authLoading && user) {
      const catParam = selectedCategory !== 'all' ? selectedCategory : undefined;
      Promise.all([
        getPersonalizedRecommendationsAction(30, catParam, excludeCompleted),
        getLibraryBooks().catch(() => ({ success: false, items: [] })),
        getUserPreferencesAction().catch(() => ({
          success: false,
          preferredGenres: [],
          preferredAuthors: [],
        })),
      ])
        .then(([recsRes, libraryRes, prefsRes]) => {
          if (ignore) return;

          if (!recsRes.isAuthenticated) {
            setIsSessionExpired(true);
            setLoading(false);
            return;
          }

          if (recsRes.success) {
            setBooks(recsRes.books || []);
            setIsColdStart(Boolean(recsRes.isColdStart));
            setEvidenceCoverage(recsRes.evidenceCoverage || null);
          } else {
            setError(recsRes.error || 'Failed to load recommendations');
          }

          if (libraryRes?.success && Array.isArray(libraryRes.items)) {
            setLibraryItems(libraryRes.items);
            const map = new Map<
              string,
              { isFavorite: boolean; status: LibraryCollectionStatus | null }
            >();
            for (const item of libraryRes.items) {
              map.set(item.bookId, {
                isFavorite: Boolean(item.isFavorite || item.status === 'favorite'),
                status: item.status,
              });
            }
            setLibraryMap(map);
          }

          if (prefsRes?.success && Array.isArray(prefsRes.preferredGenres)) {
            setPreferredGenres(prefsRes.preferredGenres);
          }
          setLoading(false);
        })
        .catch((err) => {
          if (ignore) return;
          const msg = err instanceof Error ? err.message : 'Network error';
          if (msg.toLowerCase().includes('unauthorized') || msg.includes('401')) {
            setIsSessionExpired(true);
          } else {
            setError(msg);
          }
          setLoading(false);
        });
    }

    return () => {
      ignore = true;
    };
  }, [user, authLoading, selectedCategory, excludeCompleted]);

  // Handle switching category scope (calls backend /api/recommend/personalized?category=...)
  const handleSelectCategory = (category: string) => {
    setSelectedCategory(category);
    loadData(category);
  };

  // Counts per filter tab
  const filterCounts = useMemo(() => {
    const total = books.length;
    const favorites = books.filter((b) => classifyRecommendation(b) === 'favorites').length;
    const reading = books.filter((b) => classifyRecommendation(b) === 'reading').length;
    const categoryCount = books.filter(
      (b) => classifyRecommendation(b) === 'category' || Boolean(b.categories)
    ).length;
    return { total, favorites, reading, categoryCount };
  }, [books]);

  // Filtered books
  const displayedBooks = useMemo(() => {
    let result = filterRecommendations(books, activeFilter, selectedCategory);

    if (searchQuery.trim().length > 0) {
      const q = searchQuery.toLowerCase().trim();
      result = result.filter((b) => {
        const titleMatch = (b.title || '').toLowerCase().includes(q);
        const authorMatch = (b.authors || '').toLowerCase().includes(q);
        return titleMatch || authorMatch;
      });
    }

    return result;
  }, [books, activeFilter, selectedCategory, searchQuery]);

  // Combined Category List
  const availableCategories = useMemo(() => {
    const set = new Set<string>();
    for (const g of preferredGenres) {
      if (g.trim()) set.add(g.trim());
    }
    for (const g of DEFAULT_CATEGORIES) {
      set.add(g);
    }
    return Array.from(set);
  }, [preferredGenres]);

  // Reset Personalization
  const handleResetPersonalization = async () => {
    if (!window.confirm(t('reset_personalization_confirm'))) return;
    setLoading(true);
    try {
      const res = await resetPersonalizationAction();
      if (res.success) {
        setNotice(t('reset_personalization_success'));
        await loadData();
      } else {
        setError(res.error || t('pd_reset_error'));
      }
    } catch {
      setError(t('pd_reset_error'));
    } finally {
      setLoading(false);
    }
  };

  // Next Recommended Book for Reading Journey spotlight
  const nextBook = useMemo(() => {
    return determineNextBook(books, libraryItems);
  }, [books, libraryItems]);

  // 1. Optimistic Dismiss with Rollback
  const handleDismiss = async (book: Book) => {
    const bookId = book.isbn13;
    if (pendingDismissals.has(bookId)) return;

    // Track in-flight request
    setPendingDismissals((prev) => new Set(prev).add(bookId));
    setError(null);
    setNotice(null);

    // Snapshot position and list for rollback
    const originalBooks = [...books];
    const originalIndex = books.findIndex((b) => b.isbn13 === bookId);

    // Optimistically remove from visible list
    setBooks((prev) => prev.filter((b) => b.isbn13 !== bookId));

    try {
      const res = await dismissRecommendationAction(bookId);
      if (res.success) {
        setNotice(t('recommendation_dismissed'));
        setTimeout(() => setNotice(null), 4000);
      } else {
        // Rollback
        if (originalIndex !== -1) {
          const restored = [...originalBooks];
          setBooks(restored);
        }
        setError(res.error || t('dismiss_error'));
      }
    } catch {
      // Rollback on unexpected failure
      if (originalIndex !== -1) {
        setBooks(originalBooks);
      }
      setError(t('dismiss_error'));
    } finally {
      setPendingDismissals((prev) => {
        const next = new Set(prev);
        next.delete(bookId);
        return next;
      });
    }
  };

  // 2. Optimistic Favorite Toggle with Rollback
  const handleToggleFavorite = async (bookId: string) => {
    if (pendingMutations.has(bookId)) return;

    setPendingMutations((prev) => new Set(prev).add(bookId));
    setError(null);

    const currentEntry = libraryMap.get(bookId) || { isFavorite: false, status: null };
    const nextFavorite = !currentEntry.isFavorite;

    // Optimistically update map
    setLibraryMap((prev) => {
      const next = new Map(prev);
      next.set(bookId, { ...currentEntry, isFavorite: nextFavorite });
      return next;
    });

    try {
      const res = nextFavorite
        ? await addFavoriteItem(bookId)
        : await removeFavoriteItem(bookId);

      if (!res.success) {
        // Rollback
        setLibraryMap((prev) => {
          const next = new Map(prev);
          next.set(bookId, currentEntry);
          return next;
        });
        setError(res.error || 'Failed to update favorites');
      }
    } catch {
      // Rollback
      setLibraryMap((prev) => {
        const next = new Map(prev);
        next.set(bookId, currentEntry);
        return next;
      });
      setError(t('pd_favorite_error'));
    } finally {
      setPendingMutations((prev) => {
        const next = new Set(prev);
        next.delete(bookId);
        return next;
      });
    }
  };

  // 3. Optimistic Reading Shelf Update with Rollback
  const handleUpdateShelf = async (
    bookId: string,
    newStatus: LibraryCollectionStatus | 'clear'
  ) => {
    if (pendingMutations.has(bookId)) return;

    setPendingMutations((prev) => new Set(prev).add(bookId));
    setError(null);

    const currentEntry = libraryMap.get(bookId) || { isFavorite: false, status: null };
    const nextStatus = newStatus === 'clear' ? null : newStatus;
    const previousItems = [...libraryItems];

    // Optimistically update map
    setLibraryMap((prev) => {
      const next = new Map(prev);
      next.set(bookId, { ...currentEntry, status: nextStatus });
      return next;
    });

    // Optimistically update libraryItems for instant journey reaction
    setLibraryItems((prev) => {
      if (newStatus === 'clear') {
        return prev.filter((i) => i.bookId !== bookId);
      }
      const exists = prev.some((i) => i.bookId === bookId);
      if (exists) {
        return prev.map((i) =>
          i.bookId === bookId ? { ...i, status: newStatus } : i
        );
      }
      // Book added to shelf from discovery cards
      const targetBook = books.find((b) => b.isbn13 === bookId);
      if (targetBook) {
        const newItem: LibraryItem = {
          id: bookId,
          bookId,
          status: newStatus,
          isFavorite: currentEntry.isFavorite,
          addedAt: new Date().toISOString(),
          book: targetBook,
        };
        return [newItem, ...prev];
      }
      return prev;
    });

    try {
      const res =
        newStatus === 'clear'
          ? await removeLibraryItem(bookId)
          : await updateLibraryItemStatus(bookId, newStatus);

      if (!res.success) {
        // Rollback
        setLibraryMap((prev) => {
          const next = new Map(prev);
          next.set(bookId, currentEntry);
          return next;
        });
        setLibraryItems(previousItems);
        setError(res.error || 'Failed to update reading shelf');
      }
    } catch {
      // Rollback
      setLibraryMap((prev) => {
        const next = new Map(prev);
        next.set(bookId, currentEntry);
        return next;
      });
      setLibraryItems(previousItems);
      setError(t('pd_shelf_error'));
    } finally {
      setPendingMutations((prev) => {
        const next = new Set(prev);
        next.delete(bookId);
        return next;
      });
    }
  };

  // 4. Session Expired or Unauthenticated Screen
  if (showSessionExpired) {
    return (
      <main
        className="container"
        style={{
          padding: '4rem 1rem',
          minHeight: '65vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <div
          className="glass-panel text-center animate-fade-in"
          style={{ maxWidth: '520px', width: '100%', padding: '3rem 2rem', borderRadius: '20px' }}
        >
          <div
            style={{
              width: '64px',
              height: '64px',
              borderRadius: '50%',
              background: 'rgba(99, 102, 241, 0.15)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              margin: '0 auto 1.5rem',
            }}
          >
            <Lock size={32} color="var(--primary)" />
          </div>
          <h1 style={{ fontSize: '1.85rem', marginBottom: '0.75rem' }}>
            {t('session_expired_title')}
          </h1>
          <p
            className="text-muted"
            style={{ marginBottom: '2rem', fontSize: '0.95rem', lineHeight: '1.6' }}
          >
            {t('session_expired_desc')}
          </p>
          <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap' }}>
            <Link
              href="/login?redirect=/discovery/personalized"
              className="btn btn-primary"
              id="discovery-login-btn"
            >
              {t('sign_in_to_continue')}
            </Link>
            <Link href="/signup" className="btn btn-outline">
              {t('nav_signup')}
            </Link>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className="container animate-fade-in" style={{ padding: '2.5rem 1rem 5rem' }}>
      {/* Header Banner */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-start',
          flexWrap: 'wrap',
          gap: '1.25rem',
          marginBottom: '2rem',
        }}
      >
        <div>
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.45rem',
              padding: '0.3rem 0.85rem',
              borderRadius: '9999px',
              background: 'rgba(139, 92, 246, 0.12)',
              border: '1px solid rgba(139, 92, 246, 0.28)',
              color: 'var(--accent)',
              fontSize: '0.8rem',
              fontWeight: 600,
              marginBottom: '0.75rem',
            }}
          >
            <Sparkles size={13} />
            <span>{t('personalized_discovery_badge')}</span>
          </div>

          <h1 style={{ fontSize: '2.5rem', marginBottom: '0.35rem', lineHeight: '1.15' }}>
            {t('personalized_discovery_title')}
          </h1>
          <p className="text-muted" style={{ fontSize: '1.05rem', maxWidth: '640px', margin: 0 }}>
            {t('personalized_discovery_subtitle')}
          </p>
        </div>

        {/* Action Controls: Refresh, Taste Profile, Hide Completed & Reset */}
        <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap' }}>
          <button
            type="button"
            onClick={() => setExcludeCompleted(!excludeCompleted)}
            className={`btn ${excludeCompleted ? 'btn-primary' : 'btn-outline'}`}
            style={{ padding: '0.55rem 1rem', fontSize: '0.875rem' }}
            title={excludeCompleted ? t('show_completed_books') : t('hide_completed_books')}
          >
            <EyeOff size={15} />
            <span>{excludeCompleted ? t('hide_completed_books') : t('show_completed_books')}</span>
          </button>

          <button
            type="button"
            onClick={() => setModalOpen(true)}
            className="btn btn-outline"
            style={{ padding: '0.55rem 1rem', fontSize: '0.875rem' }}
          >
            <SlidersHorizontal size={15} />
            <span>{t('taste_profile_title')}</span>
          </button>

          <button
            type="button"
            onClick={() => loadData()}
            disabled={loading}
            className="btn btn-outline"
            style={{ padding: '0.55rem 1rem', fontSize: '0.875rem' }}
            title={t('refresh')}
            aria-label={t('refresh')}
          >
            <RefreshCw size={15} className={loading ? 'animate-spin' : ''} />
            <span>{t('refresh')}</span>
          </button>

          <button
            type="button"
            onClick={handleResetPersonalization}
            disabled={loading}
            className="btn btn-outline"
            style={{ padding: '0.55rem 1rem', fontSize: '0.875rem', color: 'var(--muted)' }}
            title={t('reset_personalization')}
            aria-label={t('reset_personalization')}
          >
            <RotateCcw size={15} />
            <span>{t('reset_personalization')}</span>
          </button>
        </div>
      </div>

      {/* Success Notice / Notification Toast */}
      {notice && (
        <div
          role="status"
          className="animate-fade-in"
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.6rem',
            padding: '0.85rem 1.25rem',
            background: 'rgba(16, 185, 129, 0.12)',
            border: '1px solid rgba(16, 185, 129, 0.35)',
            color: 'var(--success, #10b981)',
            borderRadius: '12px',
            marginBottom: '1.5rem',
            fontSize: '0.9rem',
          }}
        >
          <CheckCircle2 size={18} />
          <span>{notice}</span>
        </div>
      )}

      {/* Error Alert with Retry CTA */}
      {error && (
        <div
          role="alert"
          className="animate-fade-in"
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '1rem 1.25rem',
            background: 'rgba(239, 68, 68, 0.12)',
            border: '1px solid rgba(239, 68, 68, 0.35)',
            color: 'var(--danger, #ef4444)',
            borderRadius: '12px',
            marginBottom: '1.5rem',
            fontSize: '0.9rem',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
            <AlertCircle size={18} />
            <span>{error}</span>
          </div>
          <button
            type="button"
            onClick={() => loadData()}
            className="btn btn-outline"
            style={{
              padding: '0.35rem 0.85rem',
              fontSize: '0.8rem',
              borderColor: 'rgba(239, 68, 68, 0.4)',
            }}
          >
            {t('retry')}
          </button>
        </div>
      )}

      {/* Cold Start Guidance Banner */}
      {isColdStart && (
        <div
          className="glass-panel animate-fade-in"
          style={{
            padding: '1.25rem 1.5rem',
            borderRadius: '16px',
            marginBottom: '1.5rem',
            background: 'linear-gradient(135deg, rgba(139, 92, 246, 0.12), rgba(59, 130, 246, 0.08))',
            border: '1px solid rgba(139, 92, 246, 0.25)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '1rem',
            flexWrap: 'wrap',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.85rem' }}>
            <div
              style={{
                width: '40px',
                height: '40px',
                borderRadius: '10px',
                background: 'rgba(139, 92, 246, 0.2)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'var(--accent)',
                flexShrink: 0,
              }}
            >
              <Compass size={22} />
            </div>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <h3 style={{ margin: 0, fontSize: '1rem', fontWeight: 600 }}>
                  {t('cold_start_banner_title')}
                </h3>
                <span
                  style={{
                    fontSize: '0.7rem',
                    padding: '2px 8px',
                    borderRadius: '9999px',
                    background: 'rgba(245, 158, 11, 0.2)',
                    color: '#f59e0b',
                    fontWeight: 600,
                  }}
                >
                  {t((evidenceCoverage === 'emerging' ? 'evidence_emerging' : evidenceCoverage === 'established' ? 'evidence_established' : 'evidence_cold_start') as TranslationKey)}
                </span>
              </div>
              <p
                style={{
                  margin: '0.25rem 0 0',
                  fontSize: '0.85rem',
                  color: 'var(--muted)',
                  maxWidth: '700px',
                }}
              >
                {t('cold_start_banner_desc')}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Personalized Learning Journey Dashboard */}
      <ReadingJourneyDashboard
        items={libraryItems}
        nextBook={nextBook}
        onUpdateStatus={handleUpdateShelf}
        isUpdating={pendingMutations.size > 0}
      />

      {/* Filter Tabs and Quick Search Bar */}
      <div
        className="glass-panel"
        style={{
          padding: '1.25rem',
          marginBottom: '2rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '1.25rem',
          borderRadius: '16px',
        }}
      >
        {/* Filter Tabs: all, favorites, reading, category */}
        <div className="library-tabs" role="tablist" aria-label={t('pd_filters_label')}>
          <button
            role="tab"
            aria-selected={activeFilter === 'all'}
            onClick={() => setActiveFilter('all')}
            className={`library-tab-btn ${activeFilter === 'all' ? 'active' : ''}`}
            id="filter-all"
          >
            <Sparkles size={16} />
            <span>{t('filter_all_recommendations')}</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({filterCounts.total})</span>
          </button>

          <button
            role="tab"
            aria-selected={activeFilter === 'favorites'}
            onClick={() => setActiveFilter('favorites')}
            className={`library-tab-btn ${activeFilter === 'favorites' ? 'active' : ''}`}
            id="filter-favorites"
          >
            <Heart size={16} color="#f472b6" fill={activeFilter === 'favorites' ? '#f472b6' : 'none'} />
            <span>{t('filter_favorites_derived')}</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({filterCounts.favorites})</span>
          </button>

          <button
            role="tab"
            aria-selected={activeFilter === 'reading'}
            onClick={() => setActiveFilter('reading')}
            className={`library-tab-btn ${activeFilter === 'reading' ? 'active' : ''}`}
            id="filter-reading"
          >
            <Bookmark
              size={16}
              color="var(--primary)"
              fill={activeFilter === 'reading' ? 'currentColor' : 'none'}
            />
            <span>{t('filter_reading_journey')}</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({filterCounts.reading})</span>
          </button>

          <button
            role="tab"
            aria-selected={activeFilter === 'category'}
            onClick={() => setActiveFilter('category')}
            className={`library-tab-btn ${activeFilter === 'category' ? 'active' : ''}`}
            id="filter-category"
          >
            <BookOpen size={16} color="var(--accent)" />
            <span>{t('filter_genre_category')}</span>
            <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>
              ({selectedCategory !== 'all' ? displayedBooks.length : filterCounts.categoryCount})
            </span>
          </button>
        </div>

        {/* Dynamic Category Chips row (active when 'category' tab or for quick category exploration) */}
        {activeFilter === 'category' && (
          <div
            className="animate-fade-in"
            style={{
              display: 'flex',
              gap: '0.5rem',
              alignItems: 'center',
              flexWrap: 'wrap',
              paddingTop: '0.5rem',
              borderTop: '1px solid var(--card-border)',
            }}
          >
            <span style={{ fontSize: '0.8rem', color: 'var(--muted)', fontWeight: 600 }}>
              {t('select_category_prompt')}
            </span>

            <button
              type="button"
              onClick={() => handleSelectCategory('all')}
              style={{
                fontSize: '0.78rem',
                padding: '0.3rem 0.85rem',
                borderRadius: '9999px',
                background: selectedCategory === 'all' ? 'var(--primary)' : 'rgba(255, 255, 255, 0.05)',
                color: selectedCategory === 'all' ? '#ffffff' : 'var(--foreground)',
                border: '1px solid var(--card-border)',
                cursor: 'pointer',
                transition: 'all 0.2s',
              }}
            >
              {t('category_select_all')}
            </button>

            {availableCategories.map((cat) => (
              <button
                key={cat}
                type="button"
                onClick={() => handleSelectCategory(cat)}
                style={{
                  fontSize: '0.78rem',
                  padding: '0.3rem 0.85rem',
                  borderRadius: '9999px',
                  background:
                    selectedCategory.toLowerCase() === cat.toLowerCase()
                      ? 'var(--primary)'
                      : 'rgba(255, 255, 255, 0.05)',
                  color:
                    selectedCategory.toLowerCase() === cat.toLowerCase()
                      ? '#ffffff'
                      : 'var(--foreground)',
                  border: '1px solid var(--card-border)',
                  cursor: 'pointer',
                  transition: 'all 0.2s',
                }}
              >
                {translateGenre(preferences.language, cat)}
              </button>
            ))}
          </div>
        )}

        {/* Quick Search in Recommendations */}
        <div style={{ position: 'relative', width: '100%', maxWidth: '450px' }}>
          <Search
            size={16}
            style={{
              position: 'absolute',
              left: '12px',
              top: '50%',
              transform: 'translateY(-50%)',
              color: 'var(--muted)',
            }}
          />
          <input
            type="text"
            placeholder={t('search')}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="input-field"
            style={{ width: '100%', paddingLeft: '2.4rem', height: '38px', fontSize: '0.875rem' }}
            aria-label={t('pd_search_label')}
          />
        </div>
      </div>

      {/* Loading Skeletons */}
      {loading && (
        <div className="grid-books" aria-busy="true">
          {Array.from({ length: 8 }).map((_, idx) => (
            <div
              key={idx}
              className="glass-panel animate-pulse"
              style={{ height: '380px', borderRadius: '16px' }}
            />
          ))}
        </div>
      )}

      {/* Empty State */}
      {!loading && displayedBooks.length === 0 && (
        <div
          className="glass-panel text-center animate-fade-in"
          style={{ padding: '4rem 2rem', borderRadius: '20px', margin: '2rem 0' }}
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
            {activeFilter === 'favorites' ? (
              <Heart size={28} color="#f472b6" />
            ) : activeFilter === 'reading' ? (
              <Bookmark size={28} color="var(--primary)" />
            ) : (
              <Sparkles size={28} color="var(--accent)" />
            )}
          </div>

          <h2 style={{ fontSize: '1.5rem', marginBottom: '0.5rem' }}>
            {searchQuery
              ? t('library_no_books_match', { query: searchQuery })
              : t('empty_discovery_title')}
          </h2>

          <p
            className="text-muted"
            style={{ maxWidth: '480px', margin: '0 auto 2rem', fontSize: '0.95rem', lineHeight: '1.55' }}
          >
            {searchQuery
              ? 'Try adjusting your search query or clear the input to see all suggestions.'
              : activeFilter === 'favorites'
              ? t('empty_favorites_filter_desc')
              : activeFilter === 'reading'
              ? t('empty_reading_filter_desc')
              : activeFilter === 'category' && selectedCategory !== 'all'
              ? t('empty_category_filter_desc')
              : t('empty_discovery_desc')}
          </p>

          <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'center', flexWrap: 'wrap' }}>
            <button
              type="button"
              onClick={() => {
                setActiveFilter('all');
                setSelectedCategory('all');
                setSearchQuery('');
              }}
              className="btn btn-outline"
            >
              <span>{t('filter_all_recommendations')}</span>
            </button>
            <Link href="/catalog" className="btn btn-primary">
              <Compass size={16} />
              <span>{t('explore_catalog_cta')}</span>
            </Link>
            <button
              type="button"
              onClick={() => setModalOpen(true)}
              className="btn btn-outline"
            >
              <SlidersHorizontal size={15} />
              <span>{t('taste_profile_title')}</span>
            </button>
          </div>
        </div>
      )}

      {/* Books Grid */}
      {!loading && displayedBooks.length > 0 && (
        <div className="grid-books">
          {displayedBooks.map((book) => {
            const entry = libraryMap.get(book.isbn13);
            const isFav = entry?.isFavorite ?? false;
            const status = entry?.status ?? null;
            const isDismissing = pendingDismissals.has(book.isbn13);
            const isUpdating = pendingMutations.has(book.isbn13);

            return (
              <PersonalizedDiscoveryCard
                key={book.isbn13}
                book={book}
                isFavorite={isFav}
                readingStatus={status}
                isDismissing={isDismissing}
                isUpdating={isUpdating}
                onToggleFavorite={handleToggleFavorite}
                onUpdateShelf={handleUpdateShelf}
                onDismiss={handleDismiss}
              />
            );
          })}
        </div>
      )}

      {/* Taste Profile Modal */}
      <TasteProfileModal
        isOpen={modalOpen}
        onClose={() => setModalOpen(false)}
        initialGenres={preferredGenres}
        onSaved={(newGenres) => {
          setPreferredGenres(newGenres);
          loadData();
        }}
      />
    </main>
  );
}
