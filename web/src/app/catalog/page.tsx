import { ApiService } from '@/lib/api';
import { BookCard } from '@/components/BookCard';
import type { Book, Category, PaginatedResponse } from '@/types';
import Link from 'next/link';

export const instant = false;

// Use query parameters from searchParams
export default async function CatalogPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const resolvedParams = await searchParams;
  const page = Number(resolvedParams.page) || 1;
  const category = resolvedParams.category as string | undefined;
  const q = resolvedParams.q as string | undefined;

  let booksRes: PaginatedResponse<Book> | undefined;
  let categories: Category[] = [];
  let error: string | null = null;

  try {
    // Fetch categories and books in parallel
    const [cats, bks] = await Promise.all([
      ApiService.getCategories(),
      ApiService.getBooks({ page, per_page: 20, category, query: q })
    ]);
    categories = cats;
    booksRes = bks;
  } catch (e) {
    error = 'Failed to load catalog. Please try again later.';
    console.error(e);
  }

  return (
    <div className="container animate-fade-in">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem' }}>
        <h1 style={{ fontSize: '2.5rem' }}>
          {q ? `Search: ${q}` : category ? `Category: ${category}` : 'Catalog'}
        </h1>
        
        {/* Simple Search Form */}
        <form action="/catalog" method="GET" style={{ display: 'flex', gap: '0.5rem' }}>
          <input 
            type="text" 
            name="q" 
            placeholder="Search books..." 
            defaultValue={q}
            className="input-field"
            style={{ width: '250px' }}
          />
          <button type="submit" className="btn btn-primary">Search</button>
        </form>
      </div>

      {error ? (
        <div style={{ padding: '2rem', background: 'rgba(239, 68, 68, 0.1)', color: 'var(--danger)', borderRadius: '12px' }}>
          {error}
        </div>
      ) : (
        <div style={{ display: 'flex', gap: '3rem', alignItems: 'flex-start' }}>
          {/* Categories Sidebar */}
          <aside style={{ width: '250px', flexShrink: 0, position: 'sticky', top: '100px' }}>
            <div className="glass-panel">
              <h3 style={{ marginBottom: '1rem', paddingBottom: '0.5rem', borderBottom: '1px solid var(--card-border)' }}>Categories</h3>
              <ul style={{ listStyle: 'none', display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                <li>
                  <Link 
                    href="/catalog" 
                    style={{ color: !category ? 'var(--primary)' : 'var(--foreground)', display: 'flex', justifyContent: 'space-between' }}
                  >
                    <span>All Books</span>
                  </Link>
                </li>
                {categories.map((c) => (
                  <li key={c.name}>
                    <Link 
                      href={`/catalog?category=${encodeURIComponent(c.name)}`}
                      style={{ color: category === c.name ? 'var(--primary)' : 'var(--foreground)', display: 'flex', justifyContent: 'space-between' }}
                    >
                      <span>{c.name}</span>
                      <span className="text-muted" style={{ fontSize: '0.875rem' }}>{c.count}</span>
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          </aside>

          {/* Books Grid */}
          <div style={{ flex: 1 }}>
            <p className="text-muted" style={{ marginBottom: '1rem' }}>
              Showing {booksRes?.books?.length || 0} results {booksRes?.total ? `of ${booksRes.total}` : ''}
            </p>
            
            {booksRes?.books?.length === 0 ? (
              <div className="glass-panel" style={{ textAlign: 'center', padding: '4rem 2rem' }}>
                <h3>No books found</h3>
                <p className="text-muted">Try adjusting your filters or search query.</p>
              </div>
            ) : (
              <div className="grid-books">
                {booksRes?.books?.map(book => (
                  <BookCard key={book.isbn13} book={book} />
                ))}
              </div>
            )}

            {/* Pagination */}
            {booksRes?.total_pages && booksRes.total_pages > 1 && !q && (
              <div style={{ display: 'flex', justifyContent: 'center', gap: '1rem', marginTop: '3rem' }}>
                <Link 
                  href={`/catalog?page=${Math.max(1, page - 1)}${category ? `&category=${encodeURIComponent(category)}` : ''}`}
                  className="btn btn-outline"
                  style={{ pointerEvents: page <= 1 ? 'none' : 'auto', opacity: page <= 1 ? 0.5 : 1 }}
                >
                  Previous
                </Link>
                <div style={{ display: 'flex', alignItems: 'center' }}>
                  Page {page} of {booksRes.total_pages}
                </div>
                <Link 
                  href={`/catalog?page=${Math.min(booksRes.total_pages, page + 1)}${category ? `&category=${encodeURIComponent(category)}` : ''}`}
                  className="btn btn-outline"
                  style={{ pointerEvents: page >= booksRes.total_pages ? 'none' : 'auto', opacity: page >= booksRes.total_pages ? 0.5 : 1 }}
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
