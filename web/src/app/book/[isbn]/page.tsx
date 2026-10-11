import { ApiService } from '@/lib/api';
import { BookCard } from '@/components/BookCard';
import type { Book } from '@/types';
import { Star, ArrowLeft } from 'lucide-react';
import Link from 'next/link';
import BookFeedback from '@/components/BookFeedback';

export const instant = false;

export default async function BookPage({ params }: { params: Promise<{ isbn: string }> }) {
  const { isbn } = await params;
  
  const book = await ApiService.getBookByIsbn(isbn);
  
  if (!book) {
    return (
      <div className="container" style={{ textAlign: 'center', padding: '4rem' }}>
        <h2>Book not found</h2>
        <Link href="/catalog" className="btn btn-primary" style={{ marginTop: '1rem' }}>Back to Catalog</Link>
      </div>
    );
  }

  // Fetch recommendations
  let recommendations: Book[] = [];
  try {
    recommendations = await ApiService.getRecommendations(book.title, 5);
  } catch (e) {
    console.error('Failed to fetch recommendations', e);
  }

  const thumbnailUrl = book.thumbnail && book.thumbnail !== 'None' 
    ? book.thumbnail.replace('http:', 'https:') 
    : '/fallback-book.png';

  return (
    <div className="container animate-fade-in">
      <Link href="/catalog" className="text-muted" style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem', marginBottom: '2rem' }}>
        <ArrowLeft size={16} /> Back to Catalog
      </Link>
      
      <div className="glass-panel" style={{ display: 'flex', gap: '3rem', flexWrap: 'wrap' }}>
        <div style={{ flex: '1', minWidth: '250px', maxWidth: '300px' }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img 
            src={thumbnailUrl} 
            alt={book.title} 
            style={{ width: '100%', borderRadius: '12px', boxShadow: '0 10px 30px rgba(0,0,0,0.3)' }}
          />
        </div>
        
        <div style={{ flex: '2', minWidth: '300px' }}>
          <h1 style={{ fontSize: '2.5rem', marginBottom: '0.5rem' }}>{book.title}</h1>
          <h2 style={{ fontSize: '1.25rem', color: 'var(--primary)', marginBottom: '1rem' }}>{book.authors}</h2>
          
          <div style={{ display: 'flex', gap: '1rem', marginBottom: '1.5rem', flexWrap: 'wrap' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '8px' }}>
              <Star size={18} color="#fbbf24" fill="#fbbf24" />
              <span style={{ fontWeight: 'bold' }}>{book.averageRating.toFixed(1)}</span>
              <span className="text-muted">({book.ratingsCount} ratings)</span>
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '8px' }}>
              <span className="text-muted">Pages:</span>
              <span style={{ fontWeight: 'bold' }}>{book.pageCount}</span>
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '8px' }}>
              <span className="text-muted">Published:</span>
              <span style={{ fontWeight: 'bold' }}>{book.publishedDate}</span>
            </div>
          </div>
          
          <div style={{ marginBottom: '2rem' }}>
            <h3 style={{ marginBottom: '0.5rem' }}>Categories</h3>
            <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
              {book.categories.split(',').map(cat => (
                <span key={cat} style={{ background: 'rgba(139, 92, 246, 0.2)', color: 'var(--accent)', padding: '0.25rem 0.75rem', borderRadius: '9999px', fontSize: '0.875rem' }}>
                  {cat.trim()}
                </span>
              ))}
            </div>
          </div>
          
          <div>
            <h3 style={{ marginBottom: '0.5rem' }}>Description</h3>
            <p style={{ lineHeight: '1.8', color: 'rgba(255,255,255,0.8)' }}>
              {book.description || 'No description available for this book.'}
            </p>
          </div>
          
          <BookFeedback bookId={book.isbn13} />
        </div>
      </div>
      
      {recommendations.length > 0 && (
        <div style={{ marginTop: '4rem' }}>
          <h2 style={{ fontSize: '2rem', marginBottom: '2rem' }}>Similar Books You Might Like</h2>
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
