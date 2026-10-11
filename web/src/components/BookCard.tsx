import Link from 'next/link';
import type { Book } from '@/types';
import { Star } from 'lucide-react';

export function BookCard({ book }: { book: Book }) {
  // Use HTTPS for thumbnail if needed, or fallback
  const thumbnailUrl = book.thumbnail && book.thumbnail !== 'None' 
    ? book.thumbnail.replace('http:', 'https:') 
    : '/fallback-book.png';

  return (
    <Link href={`/book/${book.isbn13}`} className="book-card animate-fade-in">
      <div className="book-cover-container">
        {/* Using a standard img tag with fallback for simplicity in the prototype */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img 
          src={thumbnailUrl} 
          alt={book.title}
          className="book-cover"
          onError={(e) => {
            (e.target as HTMLImageElement).src = '/fallback-book.png';
          }}
        />
        {book.similarityScore !== undefined && (
          <div style={{ position: 'absolute', top: 8, right: 8, background: 'var(--accent)', color: 'white', padding: '4px 8px', borderRadius: '12px', fontSize: '0.75rem', fontWeight: 'bold' }}>
            {Math.round(book.similarityScore * 100)}% Match
          </div>
        )}
      </div>
      <div>
        <h3 className="book-title">{book.title}</h3>
        <p className="book-author">{book.authors}</p>
        
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginTop: '4px' }}>
          <Star size={14} color="#fbbf24" fill="#fbbf24" />
          <span style={{ fontSize: '0.875rem', color: 'var(--muted)' }}>
            {book.averageRating > 0 ? book.averageRating.toFixed(1) : 'No rating'} 
            {book.ratingsCount > 0 && ` (${book.ratingsCount})`}
          </span>
        </div>
      </div>
    </Link>
  );
}
