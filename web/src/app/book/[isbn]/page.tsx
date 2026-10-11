import { ApiService } from '@/lib/api';
import { BookCard } from '@/components/BookCard';
import { BookCoverImage } from '@/components/BookCoverImage';
import type { Book } from '@/types';
import { Star, ArrowLeft, Calendar, FileText, Bookmark, Hash } from 'lucide-react';
import Link from 'next/link';
import BookFeedback from '@/components/BookFeedback';


export const instant = false;

export default async function BookPage({ params }: { params: Promise<{ isbn: string }> }) {
  const { isbn } = await params;
  
  const book = await ApiService.getBookByIsbn(isbn);
  
  if (!book) {
    return (
      <div className="container" style={{ textAlign: 'center', padding: '6rem 2rem' }}>
        <h2 style={{ fontSize: '2rem', marginBottom: '1rem' }}>Book Not Found</h2>
        <p className="text-muted" style={{ marginBottom: '2rem' }}>
          We couldn&apos;t find any book with ISBN <code style={{ color: 'var(--primary)' }}>{isbn}</code>.
        </p>
        <Link href="/catalog" className="btn btn-primary">
          Back to Catalog
        </Link>
      </div>
    );
  }

  // Fetch recommendations based on book title
  let recommendations: Book[] = [];
  try {
    recommendations = await ApiService.getRecommendations(book.title, 6);
  } catch (e) {
    console.error('Failed to fetch recommendations', e);
  }

  const categoryList = (book.categories || '')
    .split(',')
    .map(c => c.trim())
    .filter(Boolean);

  return (
    <div className="container animate-fade-in" style={{ paddingBottom: '5rem' }}>
      <div style={{ marginBottom: '2rem' }}>
        <Link href="/catalog" className="text-muted" style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.95rem' }}>
          <ArrowLeft size={16} /> Back to Catalog
        </Link>
      </div>
      
      <div className="glass-panel" style={{ display: 'flex', gap: '3.5rem', flexWrap: 'wrap', padding: '2.5rem' }}>
        {/* Cover Column */}
        <div style={{ flex: '1', minWidth: '240px', maxWidth: '320px' }}>
          <BookCoverImage
            thumbnail={book.thumbnail}
            title={book.title}
            authors={book.authors}
          />
        </div>
        
        {/* Details Column */}
        <div style={{ flex: '2', minWidth: '320px' }}>
          <h1 style={{ fontSize: '2.75rem', lineHeight: 1.15, marginBottom: '0.5rem' }}>{book.title}</h1>
          
          <div style={{ marginBottom: '1.5rem' }}>
            {book.authors ? (
              <Link
                href={`/catalog?q=${encodeURIComponent(book.authors)}`}
                style={{ fontSize: '1.25rem', color: 'var(--primary)', fontWeight: 500 }}
              >
                By {book.authors}
              </Link>
            ) : (
              <span style={{ fontSize: '1.25rem', color: 'var(--muted)' }}>Unknown Author</span>
            )}
          </div>
          
          {/* Metadata Badges */}
          <div style={{ display: 'flex', gap: '1rem', marginBottom: '2rem', flexWrap: 'wrap' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '10px' }}>
              <Star size={18} color="#fbbf24" fill="#fbbf24" />
              <span style={{ fontWeight: 600 }}>{book.averageRating > 0 ? book.averageRating.toFixed(1) : 'No rating'}</span>
              {book.ratingsCount > 0 && <span className="text-muted" style={{ fontSize: '0.85rem' }}>({book.ratingsCount})</span>}
            </div>
            
            {book.pageCount > 0 && (
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '10px' }}>
                <FileText size={16} color="var(--muted)" />
                <span className="text-muted">Pages:</span>
                <span style={{ fontWeight: 600 }}>{book.pageCount}</span>
              </div>
            )}
            
            {book.publishedDate && (
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '10px' }}>
                <Calendar size={16} color="var(--muted)" />
                <span className="text-muted">Published:</span>
                <span style={{ fontWeight: 600 }}>{book.publishedDate}</span>
              </div>
            )}

            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '10px' }}>
              <Hash size={16} color="var(--muted)" />
              <span className="text-muted">ISBN:</span>
              <span style={{ fontWeight: 500, fontSize: '0.85rem' }}>{book.isbn13}</span>
            </div>
          </div>
          
          {/* Categories */}
          {categoryList.length > 0 && (
            <div style={{ marginBottom: '2rem' }}>
              <h3 style={{ fontSize: '0.95rem', color: 'var(--muted)', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '0.75rem' }}>
                Genres & Categories
              </h3>
              <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
                {categoryList.map(cat => (
                  <Link
                    key={cat}
                    href={`/catalog?category=${encodeURIComponent(cat)}`}
                    style={{
                      background: 'rgba(139, 92, 246, 0.15)',
                      color: 'var(--accent)',
                      border: '1px solid rgba(139, 92, 246, 0.3)',
                      padding: '0.35rem 0.85rem',
                      borderRadius: '9999px',
                      fontSize: '0.85rem',
                      fontWeight: 500,
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '0.35rem',
                      transition: 'all 0.2s',
                    }}
                  >
                    <Bookmark size={12} />
                    <span>{cat}</span>
                  </Link>
                ))}
              </div>
            </div>
          )}
          
          {/* Synopsis */}
          <div style={{ marginBottom: '2.5rem' }}>
            <h3 style={{ fontSize: '1.2rem', marginBottom: '0.75rem' }}>Synopsis</h3>
            <p style={{ lineHeight: '1.8', color: 'rgba(255,255,255,0.85)', fontSize: '1rem', whiteSpace: 'pre-line' }}>
              {book.description || 'No description available for this book.'}
            </p>
          </div>
          
          {/* Interactive User Feedback */}
          <BookFeedback bookId={book.isbn13} />
        </div>
      </div>
      
      {/* Similar Books */}
      {recommendations.length > 0 && (
        <div style={{ marginTop: '5rem' }}>
          <div style={{ marginBottom: '2rem' }}>
            <h2 style={{ fontSize: '2rem', marginBottom: '0.25rem' }}>Similar Books You Might Like</h2>
            <p className="text-muted">Curated based on theme, genre, and reader similarity</p>
          </div>
          <div className="grid-books">
            {recommendations.map(rec => (
              <BookCard key={rec.isbn13} book={rec} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

