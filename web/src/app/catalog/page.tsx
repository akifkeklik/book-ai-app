import { ApiService } from '@/lib/api';
import { BookCard } from '@/components/BookCard';
import type { Book, Category, PaginatedResponse } from '@/types';
import Link from 'next/link';
import { Search, SlidersHorizontal, X, ArrowUpDown, Star, BookOpen } from 'lucide-react';


export const instant = false;

export default async function CatalogPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const resolvedParams = await searchParams;
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

  const createFilterUrl = (overrides: Record<string, string | number | undefined | null>) => {
    const params = new URLSearchParams();
    if (category) params.set('category', category);
    if (q) params.set('q', q);
    if (sort && sort !== 'popularity') params.set('sort', sort);
    if (order && order !== 'desc') params.set('order', order);
    if (minRating) params.set('min_rating', String(minRating));

    // Reset page to 1 when changing filters, unless explicitly passing page
    if (!('page' in overrides)) {
      params.delete('page');
    }

    for (const [key, value] of Object.entries(overrides)) {
      if (value === undefined || value === null || value === '') {
        params.delete(key);
      } else {
        params.set(key, String(value));
      }
    }

    const queryStr = params.toString();
    return queryStr ? `/catalog?${queryStr}` : '/catalog';
  };

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
              {q ? `Search: "${q}"` : category ? `${category}` : 'Explore Catalog'}
            </h1>
            <p className="text-muted">
              {q ? `Matching books for your query` : category ? `Discover books in ${category}` : 'Browse all books, filter by genre, or search by title and author'}
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
                placeholder="Search title, author, description..." 
                defaultValue={q}
                className="input-field"
                style={{ width: '100%', paddingLeft: '2.5rem', paddingRight: q ? '2.5rem' : '1rem' }}
              />
              <Search size={18} style={{ position: 'absolute', left: '0.85rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--muted)' }} />
              {q && (
                <Link
                  href={createFilterUrl({ q: null })}
                  style={{ position: 'absolute', right: '0.85rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--muted)' }}
                  aria-label="Clear search"
                >
                  <X size={16} />
                </Link>
              )}
            </div>
            <button type="submit" className="btn btn-primary" style={{ padding: '0.75rem 1.25rem' }}>
              Search
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
              <span style={{ fontSize: '0.875rem', color: 'var(--muted)' }}>Sort:</span>
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
                  Popular
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
                  Top Rated
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
                  Title A-Z
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
                  Newest
                </Link>
              </div>
            </div>

            {/* Min Rating Filter */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <Star size={16} color="#fbbf24" fill="#fbbf24" />
              <span style={{ fontSize: '0.875rem', color: 'var(--muted)' }}>Min Rating:</span>
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
            Reload Catalog
          </Link>
        </div>
      ) : (
        <div style={{ display: 'flex', gap: '2.5rem', alignItems: 'flex-start' }}>
          {/* Categories Sidebar */}
          <aside style={{ width: '260px', flexShrink: 0, position: 'sticky', top: '100px' }}>
            <div className="glass-panel" style={{ maxHeight: '75vh', overflowY: 'auto' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1rem', paddingBottom: '0.5rem', borderBottom: '1px solid var(--card-border)' }}>
                <SlidersHorizontal size={18} color="var(--primary)" />
                <h3 style={{ fontSize: '1.1rem', margin: 0 }}>Categories</h3>
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
                    <span>All Books</span>
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
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem' }}>
              <p className="text-muted" style={{ fontSize: '0.9rem' }}>
                Showing {displayedBooks.length} books {totalBooks ? `of ${totalBooks}` : ''} {page > 1 ? `(Page ${page})` : ''}
              </p>
            </div>
            
            {displayedBooks.length === 0 ? (
              <div className="glass-panel" style={{ textAlign: 'center', padding: '4rem 2rem' }}>
                <BookOpen size={48} style={{ opacity: 0.3, margin: '0 auto 1rem' }} />
                <h3 style={{ fontSize: '1.4rem', marginBottom: '0.5rem' }}>No books match your criteria</h3>
                <p className="text-muted" style={{ maxWidth: '400px', margin: '0 auto 1.5rem' }}>
                  We couldn&apos;t find any books with the selected search terms and filters. Try clearing your search query or choosing another category.
                </p>
                <Link href="/catalog" className="btn btn-primary">
                  Reset All Filters
                </Link>
              </div>
            ) : (
              <div className="grid-books">
                {displayedBooks.map((book) => (
                  <BookCard key={book.isbn13} book={book} />
                ))}
              </div>
            )}

            {/* Pagination Controls */}
            {totalPages > 1 && (
              <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: '1rem', marginTop: '3.5rem' }}>
                <Link 
                  href={createFilterUrl({ page: Math.max(1, page - 1) })}
                  className="btn btn-outline"
                  style={{ pointerEvents: page <= 1 ? 'none' : 'auto', opacity: page <= 1 ? 0.4 : 1 }}
                >
                  Previous
                </Link>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', color: 'var(--muted)', fontSize: '0.95rem' }}>
                  <span>Page <strong style={{ color: 'var(--foreground)' }}>{page}</strong> of {totalPages}</span>
                </div>
                <Link 
                  href={createFilterUrl({ page: Math.min(totalPages, page + 1) })}
                  className="btn btn-outline"
                  style={{ pointerEvents: page >= totalPages ? 'none' : 'auto', opacity: page >= totalPages ? 0.4 : 1 }}
                >
                  Next
                </Link>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

