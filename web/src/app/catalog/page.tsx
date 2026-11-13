import { ApiService } from '@/lib/api';
import { CatalogBookList } from '@/components/CatalogBookList';
import type { Book, Category, PaginatedResponse } from '@/types';
import Link from 'next/link';
import { Search, SlidersHorizontal, X, ArrowUpDown, Star, BookOpen } from 'lucide-react';
import { cookies } from 'next/headers';
import { translate, type TranslationKey } from '@/lib/i18n';
import { type Language, resolveLanguage } from '@/lib/preferences';
import { buildCatalogUrl, type CatalogFilterState, type CatalogUrlOverrides } from '@/lib/catalogUrl';

export const dynamic = 'force-dynamic';

export default async function CatalogPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const resolvedParams = await searchParams;
  const cookieStore = await cookies();
  const rawLang = cookieStore.get('libris_lang')?.value;
  const lang: Language = resolveLanguage(rawLang);
  const t = (key: TranslationKey, args?: Record<string, string | number>) => translate(lang, key, args);

  const page = Math.max(1, Number(resolvedParams.page) || 1);
  const category = (resolvedParams.category as string) || '';
  const q = (resolvedParams.q as string) || '';
  const sort = (resolvedParams.sort as string) || 'popularity';
  const order = (resolvedParams.order as 'asc' | 'desc') || (sort === 'title' ? 'asc' : 'desc');
  const minRating = resolvedParams.min_rating ? Number(resolvedParams.min_rating) : undefined;

  let booksRes: PaginatedResponse<Book> | undefined;
  let categories: Category[] = [];
  let error: string | null = null;

  try {
    const [cats, bks] = await Promise.all([
      ApiService.getCategories(),
      ApiService.getBooks({
        page,
        per_page: 20,
        category: category || undefined,
        query: q || undefined,
        sort,
        order,
        min_rating: minRating,
      }),
    ]);
    categories = cats;
    booksRes = bks;
  } catch (e) {
    error = 'Failed to load catalog. Please check your connection and try again.';
    console.error(e);
  }

  const hasActiveFilters = Boolean(q || category || (sort && sort !== 'popularity') || minRating);

  const filterState: CatalogFilterState = {
    category: category || undefined,
    query: q || undefined,
    sort: sort || undefined,
    order: order || undefined,
    min_rating: minRating,
  };
  const createFilterUrl = (overrides: CatalogUrlOverrides) => buildCatalogUrl(filterState, overrides);

  const totalPages = booksRes?.total_pages || 1;
  const totalBooks = booksRes?.total || 0;
  const displayedBooks = booksRes?.books || [];

  return (
    <div className="container animate-fade-in" style={{ paddingBottom: '4rem' }}>
      {/* Search & Header Section */}
      <div style={{ marginBottom: '2.5rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1.5rem', marginBottom: '1.5rem' }}>
          <div>
            <h1 style={{ fontSize: '2.5rem', marginBottom: '0.25rem' }}>
              {q ? `Search: "${q}"` : category ? `${category}` : t('catalog_title')}
            </h1>
            <p className="text-muted">
              {q ? `Matching books for your query` : category ? `Discover books in ${category}` : t('catalog_subtitle')}
            </p>
          </div>

          {/* Unified Search Form */}
          <form action="/catalog" method="GET" style={{ display: 'flex', gap: '0.5rem', flex: '1', maxWidth: '400px' }}>
            {category && <input type="hidden" name="category" value={category} />}
            {sort && <input type="hidden" name="sort" value={sort} />}
            {order && <input type="hidden" name="order" value={order} />}
            {minRating && <input type="hidden" name="min_rating" value={minRating} />}
            <div style={{ position: 'relative', width: '100%' }}>
              <input 
                type="text" 
                name="q" 
                placeholder={t('search_placeholder')} 
                defaultValue={q}
                className="input-field"
                style={{ width: '100%', paddingLeft: '2.5rem', paddingRight: q ? '2.5rem' : '1rem' }}
              />
              <Search size={18} style={{ position: 'absolute', left: '0.85rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--muted)' }} />
              {q && (
                <Link
                  href={createFilterUrl({ q: null })}
                  style={{ position: 'absolute', right: '0.85rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--muted)' }}
                  aria-label={t('clear_search')}
                >
                  <X size={16} />
                </Link>
              )}
            </div>
            <button type="submit" className="btn btn-primary" style={{ padding: '0.75rem 1.25rem' }}>
              {t('search')}
            </button>
          </form>
        </div>

        {/* Filter Bar: Sort, Rating, Active Badges */}
        <div
          className="glass-panel"
          style={{
            padding: '1rem 1.5rem',
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            flexWrap: 'wrap',
            gap: '1rem',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap' }}>
            {/* Sort Control */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <ArrowUpDown size={16} color="var(--muted)" />
              <span style={{ fontSize: '0.875rem', color: 'var(--muted)' }}>{t('sort_label')}</span>
              <div style={{ display: 'flex', gap: '0.4rem' }}>
                <Link
                  href={createFilterUrl({ sort: 'popularity', order: 'desc' })}
                  className="btn"
                  style={{
                    padding: '0.35rem 0.75rem',
                    fontSize: '0.8rem',
                    background: sort === 'popularity' ? 'var(--primary)' : 'rgba(255,255,255,0.05)',
                    color: sort === 'popularity' ? '#fff' : 'var(--foreground)',
                  }}
                >
                  {t('sort_popularity')}
                </Link>
                <Link
                  href={createFilterUrl({ sort: 'rating', order: 'desc' })}
                  className="btn"
                  style={{
                    padding: '0.35rem 0.75rem',
                    fontSize: '0.8rem',
                    background: sort === 'rating' ? 'var(--primary)' : 'rgba(255,255,255,0.05)',
                    color: sort === 'rating' ? '#fff' : 'var(--foreground)',
                  }}
                >
                  {t('sort_rating')}
                </Link>
                <Link
                  href={createFilterUrl({ sort: 'title', order: 'asc' })}
                  className="btn"
                  style={{
                    padding: '0.35rem 0.75rem',
                    fontSize: '0.8rem',
                    background: sort === 'title' ? 'var(--primary)' : 'rgba(255,255,255,0.05)',
                    color: sort === 'title' ? '#fff' : 'var(--foreground)',
                  }}
                >
                  {t('sort_title')}
                </Link>
                <Link
                  href={createFilterUrl({ sort: 'newest', order: 'desc' })}
                  className="btn"
                  style={{
                    padding: '0.35rem 0.75rem',
                    fontSize: '0.8rem',
                    background: sort === 'newest' ? 'var(--primary)' : 'rgba(255,255,255,0.05)',
                    color: sort === 'newest' ? '#fff' : 'var(--foreground)',
                  }}
                >
                  {t('sort_newest')}
                </Link>
              </div>
            </div>

            {/* Min Rating Filter */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <Star size={16} color="#fbbf24" fill="#fbbf24" />
              <span style={{ fontSize: '0.875rem', color: 'var(--muted)' }}>{t('min_rating_label')}</span>
              <div style={{ display: 'flex', gap: '0.4rem' }}>
                <Link
                  href={createFilterUrl({ min_rating: null })}
                  className="btn"
                  style={{
                    padding: '0.35rem 0.65rem',
                    fontSize: '0.8rem',
                    background: !minRating ? 'rgba(255,255,255,0.15)' : 'rgba(255,255,255,0.05)',
                    color: 'var(--foreground)',
                  }}
                >
                  All
                </Link>
                <Link
                  href={createFilterUrl({ min_rating: 4 })}
                  className="btn"
                  style={{
                    padding: '0.35rem 0.65rem',
                    fontSize: '0.8rem',
                    background: minRating === 4 ? '#fbbf24' : 'rgba(255,255,255,0.05)',
                    color: minRating === 4 ? '#000' : 'var(--foreground)',
                    fontWeight: minRating === 4 ? 600 : 400,
                  }}
                >
                  4★+
                </Link>
                <Link
                  href={createFilterUrl({ min_rating: 3 })}
                  className="btn"
                  style={{
                    padding: '0.35rem 0.65rem',
                    fontSize: '0.8rem',
                    background: minRating === 3 ? '#fbbf24' : 'rgba(255,255,255,0.05)',
                    color: minRating === 3 ? '#000' : 'var(--foreground)',
                    fontWeight: minRating === 3 ? 600 : 400,
                  }}
                >
                  3★+
                </Link>
              </div>
            </div>
          </div>

          {/* Active Filter Clear */}
          {hasActiveFilters && (
            <Link
              href="/catalog"
              className="btn btn-outline"
              style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem', color: 'var(--danger)', borderColor: 'rgba(239, 68, 68, 0.4)' }}
            >
              <X size={14} /> Clear all filters
            </Link>
          )}
        </div>
      </div>

      {error ? (
        <div style={{ padding: '2rem', background: 'rgba(239, 68, 68, 0.1)', color: 'var(--danger)', borderRadius: '12px', textAlign: 'center' }}>
          <p style={{ fontWeight: 600, marginBottom: '0.5rem' }}>{error}</p>
          <Link href="/catalog" className="btn btn-primary" style={{ marginTop: '1rem' }}>
            {t('reload_catalog')}
          </Link>
        </div>
      ) : (
        <div className="catalog-layout">
          {/* Categories Sidebar */}
          <aside className="catalog-sidebar">
            <div className="glass-panel" style={{ maxHeight: '75vh', overflowY: 'auto' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1rem', paddingBottom: '0.5rem', borderBottom: '1px solid var(--card-border)' }}>
                <SlidersHorizontal size={18} color="var(--primary)" />
                <h3 style={{ fontSize: '1.1rem', margin: 0 }}>{t('categories_filter')}</h3>
              </div>
              <ul style={{ listStyle: 'none', display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
                <li>
                  <Link 
                    href={createFilterUrl({ category: null })} 
                    style={{
                      color: !category ? 'var(--primary)' : 'var(--foreground)',
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      padding: '0.4rem 0.6rem',
                      borderRadius: '8px',
                      background: !category ? 'rgba(59, 130, 246, 0.15)' : 'transparent',
                      fontWeight: !category ? 600 : 400,
                    }}
                  >
                    <span>{t('tab_all')}</span>
                    <span className="text-muted" style={{ fontSize: '0.8rem' }}>{totalBooks > 0 ? totalBooks : ''}</span>
                  </Link>
                </li>
                {categories.map((c) => {
                  const isSelected = category === c.name;
                  return (
                    <li key={c.name}>
                      <Link 
                        href={createFilterUrl({ category: isSelected ? null : c.name })}
                        style={{
                          color: isSelected ? 'var(--primary)' : 'var(--foreground)',
                          display: 'flex',
                          justifyContent: 'space-between',
                          alignItems: 'center',
                          padding: '0.4rem 0.6rem',
                          borderRadius: '8px',
                          background: isSelected ? 'rgba(59, 130, 246, 0.15)' : 'transparent',
                          fontWeight: isSelected ? 600 : 400,
                        }}
                      >
                        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', marginRight: '0.5rem' }}>
                          {c.name}
                        </span>
                        <span className="text-muted" style={{ fontSize: '0.8rem', flexShrink: 0 }}>{c.count}</span>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </div>
          </aside>

          {/* Books Grid */}
          <div className="catalog-content">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem' }}>
              <p className="text-muted" style={{ fontSize: '0.9rem' }}>
                Showing {displayedBooks.length} books {totalBooks ? `of ${totalBooks}` : ''} {page > 1 ? `(Page ${page})` : ''}
              </p>
            </div>
            
            {displayedBooks.length === 0 ? (
              <div className="glass-panel" style={{ textAlign: 'center', padding: '3.5rem 2rem' }} data-testid="empty-catalog-state">
                <BookOpen size={48} style={{ opacity: 0.3, margin: '0 auto 1rem' }} />
                {q && category ? (
                  <>
                    <h3 style={{ fontSize: '1.4rem', marginBottom: '0.5rem' }}>
                      No books found for &ldquo;{q}&rdquo; in {category}
                    </h3>
                    <p className="text-muted" style={{ maxWidth: '520px', margin: '0 auto 1.5rem', lineHeight: '1.6' }}>
                      The active category filter excludes matching catalog entries. You can expand your search across all categories or browse all titles in {category}.
                    </p>
                    <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'center', flexWrap: 'wrap', marginBottom: '1.5rem' }}>
                      <Link
                        href={createFilterUrl({ category: null })}
                        className="btn btn-primary"
                        style={{ padding: '0.5rem 1.25rem' }}
                      >
                        Search &ldquo;{q}&rdquo; in All Categories
                      </Link>
                      <Link
                        href={createFilterUrl({ q: null })}
                        className="btn btn-outline"
                        style={{ padding: '0.5rem 1.25rem' }}
                      >
                        Browse All in {category}
                      </Link>
                      <Link
                        href="/catalog"
                        className="btn"
                        style={{ padding: '0.5rem 1rem', background: 'rgba(255, 255, 255, 0.06)' }}
                      >
                        {t('clear_filters')}
                      </Link>
                    </div>
                  </>
                ) : q ? (
                  <>
                    <h3 style={{ fontSize: '1.4rem', marginBottom: '0.5rem' }}>
                      No books match &ldquo;{q}&rdquo;
                    </h3>
                    <p className="text-muted" style={{ maxWidth: '440px', margin: '0 auto 1.5rem', lineHeight: '1.6' }}>
                      We couldn&apos;t find any books with that title, author, or ISBN. Try clearing your search query or explore one of these popular genres:
                    </p>
                    <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'center', flexWrap: 'wrap', maxWidth: '480px', margin: '0 auto 1.5rem' }}>
                      {['Fiction', 'Science', 'History', 'Philosophy', 'Mystery & Thriller', 'Fantasy'].map((suggestedGenre) => (
                        <Link
                          key={suggestedGenre}
                          href={`/catalog?category=${encodeURIComponent(suggestedGenre)}`}
                          className="btn"
                          style={{
                            padding: '0.4rem 0.85rem',
                            fontSize: '0.8rem',
                            background: 'rgba(255, 255, 255, 0.06)',
                            border: '1px solid var(--card-border)',
                            color: 'var(--foreground)',
                          }}
                        >
                          {suggestedGenre}
                        </Link>
                      ))}
                    </div>
                    <Link href="/catalog" className="btn btn-primary">
                      {t('clear_search')}
                    </Link>
                  </>
                ) : category ? (
                  <>
                    <h3 style={{ fontSize: '1.4rem', marginBottom: '0.5rem' }}>
                      No books found in {category}
                    </h3>
                    <p className="text-muted" style={{ maxWidth: '440px', margin: '0 auto 1.5rem', lineHeight: '1.6' }}>
                      {t('catalog_empty_category')}
                    </p>
                    <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'center', flexWrap: 'wrap' }}>
                      <Link href="/catalog" className="btn btn-primary">
                        {t('browse_all_books')}
                      </Link>
                    </div>
                  </>
                ) : (
                  <>
                    <h3 style={{ fontSize: '1.4rem', marginBottom: '0.5rem' }}>{t('catalog_no_match')}</h3>
                    <p className="text-muted" style={{ maxWidth: '420px', margin: '0 auto 1.5rem', lineHeight: '1.6' }}>
                      {t('catalog_adjust_filters')}
                    </p>
                    <Link href="/catalog" className="btn btn-primary">
                      {t('clear_filters')}
                    </Link>
                  </>
                )}
              </div>
            ) : (
              <CatalogBookList
                initialBooks={displayedBooks}
                initialPage={page}
                totalPages={totalPages}
                totalBooks={totalBooks}
                filterParams={filterState}
              />
            )}
          </div>
        </div>
      )}
    </div>
  );
}

