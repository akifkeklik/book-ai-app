import { ApiService } from '@/lib/api';
import { BookCard } from '@/components/BookCard';
import { BookCoverImage } from '@/components/BookCoverImage';
import type { Book } from '@/types';
import { Star, ArrowLeft, Calendar, FileText, Bookmark, Hash, AlertTriangle, RefreshCw } from 'lucide-react';
import Link from 'next/link';
import BookFeedback from '@/components/BookFeedback';
import BookNotesWidget from '@/components/BookNotesWidget';
import { getBookNotes } from '@/app/actions/notes';
import type { LearningNote } from '@/types';
import { getBookInteraction } from '@/app/actions/library';
import { cookies } from 'next/headers';
import { translate, translateGenre, type TranslationKey } from '@/lib/i18n';
import { resolveLanguage } from '@/lib/preferences';
import { formatCount, formatRating } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function BookPage({ params }: { params: Promise<{ isbn: string }> }) {
  const cookieStore = await cookies();
  const lang = resolveLanguage(cookieStore.get('libris_lang')?.value);
  const t = (key: TranslationKey, args?: Record<string, string | number>) => translate(lang, key, args);
  const { isbn } = await params;
  
  let book: Book | null = null;
  let serviceError: { isTimeout: boolean; message: string } | null = null;

  try {
    book = await ApiService.getBookByIsbn(isbn);
  } catch (err: unknown) {
    const isTimeout =
      (err as { isTimeout?: boolean })?.isTimeout === true ||
      (err instanceof Error && (err.name === 'ApiTimeoutError' || err.message.toLowerCase().includes('timeout')));
    serviceError = {
      isTimeout,
      message: isTimeout
        ? 'The book catalog service timed out. Please check your connection and try again.'
        : 'The book catalog service is temporarily unavailable. Please try again shortly.',
    };
  }

  // Controlled UI for network / timeout / 5xx service errors
  if (serviceError) {
    return (
      <div className="container" style={{ textAlign: 'center', padding: '6rem 2rem' }}>
        <div
          className="glass-panel"
          style={{
            maxWidth: '560px',
            margin: '0 auto',
            padding: '3rem 2rem',
            borderRadius: '16px',
          }}
        >
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '64px',
              height: '64px',
              borderRadius: '50%',
              background: 'rgba(239, 68, 68, 0.15)',
              color: 'var(--danger, #ef4444)',
              marginBottom: '1.5rem',
            }}
          >
            <AlertTriangle size={32} />
          </div>
          <h2 style={{ fontSize: '1.75rem', marginBottom: '0.75rem' }}>
            {t('book_service_unavailable')}
          </h2>
          <p className="text-muted" style={{ marginBottom: '2rem', lineHeight: '1.6' }}>
            {serviceError.message}
          </p>
          <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap' }}>
            <Link
              href={`/book/${encodeURIComponent(isbn)}`}
              className="btn btn-primary"
              style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem' }}
            >
              <RefreshCw size={16} /> Retry
            </Link>
            <Link
              href="/catalog"
              className="btn"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.5rem',
                background: 'rgba(255, 255, 255, 0.08)',
              }}
            >
              <ArrowLeft size={16} /> {t('back_to_catalog')}
            </Link>
          </div>
        </div>
      </div>
    );
  }

  // 404 / Book Not Found
  if (!book) {
    return (
      <div className="container" style={{ textAlign: 'center', padding: '6rem 2rem' }}>
        <h2 style={{ fontSize: '2rem', marginBottom: '1rem' }}>{t('book_not_found')}</h2>
        <p className="text-muted" style={{ marginBottom: '2rem' }}>
          We couldn&apos;t find any book with ISBN <code style={{ color: 'var(--primary)' }}>{isbn}</code>.
        </p>
        <Link href="/catalog" className="btn btn-primary">
          {t('back_to_catalog')}
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

  // Retrieve verified server-side user interaction
  let initialInteraction: string | null = null;
  let initialIsFavorite = false;
  let interactionError: string | null = null;
  let isAuthenticated = false;

  let initialNotes: LearningNote[] = [];
  try {
    const notesResult = await getBookNotes(book.isbn13);
    if (notesResult.success) {
      initialNotes = notesResult.notes;
    }
  } catch {
    // Non-fatal
  }

  try {
    const interResult = await getBookInteraction(book.isbn13);
    isAuthenticated = interResult.isAuthenticated;
    if (interResult.success) {
      initialInteraction = interResult.interaction;
      initialIsFavorite = !!interResult.isFavorite;
    } else {
      interactionError = interResult.error || 'Could not verify existing activity';
    }
  } catch (err: unknown) {
    interactionError = err instanceof Error ? err.message : 'Could not check interaction';
  }

  const categoryList = (book.categories || '')
    .split(',')
    .map(c => c.trim())
    .filter(Boolean);

  return (
    <div className="container animate-fade-in" style={{ paddingBottom: '5rem' }}>
      <div style={{ marginBottom: '2rem' }}>
        <Link href="/catalog" className="text-muted" style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.95rem' }}>
          <ArrowLeft size={16} /> {t('back_to_catalog')}
        </Link>
      </div>
      
      <div className="glass-panel" style={{ display: 'flex', gap: '2.5rem', flexWrap: 'wrap', padding: 'clamp(1rem, 4vw, 2.5rem)', maxWidth: '100%', overflowX: 'hidden' }}>
        {/* Cover Column */}
        <div style={{ flex: '1 1 200px', minWidth: '0', maxWidth: '320px', width: '100%' }}>
          <BookCoverImage
            thumbnail={book.thumbnail}
            title={book.title}
            authors={book.authors}
          />
        </div>
        
        {/* Details Column */}
        <div style={{ flex: '2 1 260px', minWidth: '0', maxWidth: '100%' }}>
          <h1 style={{ fontSize: 'clamp(1.75rem, 5vw, 2.75rem)', lineHeight: 1.15, marginBottom: '0.5rem', wordBreak: 'break-word' }}>{book.title}</h1>
          
          <div style={{ marginBottom: '1.5rem' }}>
            {book.authors ? (
              <Link
                href={`/catalog?q=${encodeURIComponent(book.authors)}`}
                style={{ fontSize: '1.25rem', color: 'var(--primary)', fontWeight: 500 }}
              >
                By {book.authors}
              </Link>
            ) : (
              <span style={{ fontSize: '1.25rem', color: 'var(--muted)' }}>{t('unknown_author')}</span>
            )}
          </div>
          
          {/* Metadata Badges */}
          <div style={{ display: 'flex', gap: '1rem', marginBottom: '2rem', flexWrap: 'wrap' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '10px' }}>
              <Star size={18} color="#fbbf24" fill="#fbbf24" />
              <span style={{ fontWeight: 600 }}>{book.averageRating > 0 ? formatRating(book.averageRating, lang) : t('no_rating')}</span>
              {book.ratingsCount > 0 && <span className="text-muted" style={{ fontSize: '0.85rem' }}>({formatCount(book.ratingsCount, lang)})</span>}
            </div>
            
            {book.pageCount > 0 && (
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '10px' }}>
                <FileText size={16} color="var(--muted)" />
                <span className="text-muted">{t('book_pages_label')}</span>
                <span style={{ fontWeight: 600 }}>{book.pageCount}</span>
              </div>
            )}
            
            {book.publishedDate && (
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'rgba(255,255,255,0.05)', padding: '0.5rem 1rem', borderRadius: '10px' }}>
                <Calendar size={16} color="var(--muted)" />
                <span className="text-muted">{t('book_published_label')}</span>
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
                {t('book_genres_label')}
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
                    <span>{translateGenre(lang, cat)}</span>
                  </Link>
                ))}
              </div>
            </div>
          )}
          
          {/* Synopsis */}
          <div style={{ marginBottom: '2.5rem' }}>
            <h3 style={{ fontSize: '1.2rem', marginBottom: '0.75rem' }}>{t('book_synopsis')}</h3>
            <p style={{ lineHeight: '1.8', color: 'rgba(255,255,255,0.85)', fontSize: '1rem', whiteSpace: 'pre-line' }}>
              {book.description || 'No description available for this book.'}
            </p>
          </div>
          
          {/* Interactive User Feedback */}
          <BookFeedback
            bookId={book.isbn13}
            initialInteraction={initialInteraction}
            initialIsFavorite={initialIsFavorite}
            interactionError={interactionError}
            isAuthenticated={isAuthenticated}
          />

          {/* Learning Notes & Knowledge Retention */}
          <BookNotesWidget
            bookId={book.isbn13}
            initialNotes={initialNotes}
            isAuthenticated={isAuthenticated}
          />
        </div>
      </div>
      
      {/* Similar Books */}
      {recommendations.length > 0 && (
        <div style={{ marginTop: '5rem' }}>
          <div style={{ marginBottom: '2rem' }}>
            <h2 style={{ fontSize: '2rem', marginBottom: '0.25rem' }}>{t('book_similar_title')}</h2>
            <p className="text-muted">{t('book_similar_subtitle')}</p>
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
