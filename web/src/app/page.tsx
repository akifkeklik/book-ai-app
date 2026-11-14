import Link from 'next/link';
import { BookOpen, Sparkles, Compass, Library, TrendingUp, ArrowRight, Bookmark } from 'lucide-react';
import { cookies } from 'next/headers';
import { createClient } from '@/lib/supabase/server';
import { ApiService } from '@/lib/api';
import { BookCard } from '@/components/BookCard';
import { HomePersonalizationBanner } from '@/components/HomePersonalizationBanner';
import { ReadingJourneyDashboard } from '@/components/ReadingJourneyDashboard';
import { getLibraryBooks } from '@/app/actions/library';
import { translate, translateGenre, type TranslationKey } from '@/lib/i18n';
import { type Language, resolveLanguage } from '@/lib/preferences';
import type { Book, LibraryItem } from '@/types';
import { SmartReviewWidget } from '@/components/SmartReviewWidget';

export const dynamic = 'force-dynamic';

const POPULAR_GENRES = [
  'Fiction',
  'Science',
  'History',
  'Mystery',
  'Philosophy',
  'Biography',
  'Psychology',
  'Romance',
  'Fantasy',
];

export default async function Home({
  searchParams,
}: {
  searchParams?: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const resolvedParams = searchParams ? await searchParams : {};
  const autoOpenOnboarding = resolvedParams?.onboarding === 'true';

  const cookieStore = await cookies();
  const rawLang = cookieStore.get('libris_lang')?.value;
  const lang: Language = resolveLanguage(rawLang);
  const t = (key: TranslationKey, args?: Record<string, string | number>) => translate(lang, key, args);

  const supabase = await createClient();
  const { data: { session } } = await supabase.auth.getSession();
  
  let personalizedRecs: Book[] = [];
  let featuredBooks: Book[] = [];
  let readingBooks: Book[] = [];
  let wantToReadBooks: Book[] = [];
  let libraryItems: LibraryItem[] = [];
  let becauseYouEnjoyBooks: Book[] = [];
  let primaryGenre = '';
  let userPreferredGenres: string[] = [];

  try {
    const popularPromise = ApiService.getBooks({ per_page: 8, sort: 'popularity', order: 'desc' })
      .then((res) => res.books)
      .catch(() => []);

    if (session) {
      const [popularResult, recsResult, libraryResult, prefsResult] = await Promise.all([
        popularPromise,
        ApiService.getPersonalizedRecommendations(8).catch((err) => {
          console.error('Personalized recs error:', err);
          return [];
        }),
        getLibraryBooks().catch(() => ({ success: false, items: [] })),
        ApiService.getUserPreferences().catch(() => ({ preferredGenres: [], preferredAuthors: [] })),
      ]);

      featuredBooks = popularResult || [];
      personalizedRecs = recsResult || [];
      userPreferredGenres = prefsResult?.preferredGenres || [];

      if (libraryResult?.success && Array.isArray(libraryResult.items)) {
        libraryItems = libraryResult.items;
        readingBooks = libraryResult.items
          .filter((item) => item.status === 'reading' && item.book)
          .map((item) => item.book!);
        wantToReadBooks = libraryResult.items
          .filter((item) => item.status === 'want_to_read' && item.book)
          .map((item) => item.book!);
      }

      if (userPreferredGenres.length > 0) {
        primaryGenre = userPreferredGenres[0];
        try {
          const genreBooksRes = await ApiService.getBooks({
            category: primaryGenre,
            per_page: 4,
            sort: 'popularity',
            order: 'desc',
          });
          becauseYouEnjoyBooks = genreBooksRes.books || [];
        } catch {
          becauseYouEnjoyBooks = [];
        }
      }
    } else {
      featuredBooks = (await popularPromise) || [];
    }
  } catch (e) {
    console.error('Failed to load home page discovery data:', e);
  }

  return (
    <div className="container" style={{ padding: '3.5rem 1.5rem', maxWidth: '1200px' }}>
      {/* Hero Section */}
      <div className="animate-fade-in" style={{ textAlign: 'center', maxWidth: '840px', margin: '0 auto 4rem' }}>
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.5rem',
            padding: '0.4rem 1rem',
            borderRadius: '9999px',
            background: 'rgba(99, 102, 241, 0.1)',
            border: '1px solid rgba(99, 102, 241, 0.25)',
            marginBottom: '1.5rem',
            fontSize: '0.85rem',
            fontWeight: 600,
            color: '#a5b4fc',
          }}
        >
          <Sparkles size={14} color="#818cf8" />
          <span>{t('hero_badge')}</span>
        </div>

        <h1
          style={{
            fontSize: 'clamp(2.5rem, 5.5vw, 4.25rem)',
            marginBottom: '1.5rem',
            lineHeight: 1.12,
            fontWeight: 700,
          }}
        >
          {t('hero_title')}
        </h1>

        <p
          className="text-muted"
          style={{
            fontSize: 'clamp(1rem, 2vw, 1.25rem)',
            lineHeight: 1.6,
            marginBottom: '2.5rem',
            maxWidth: '680px',
            marginInline: 'auto',
          }}
        >
          {t('hero_subtitle')}
        </p>
        
        {/* Action CTAs */}
        <div
          style={{
            display: 'flex',
            gap: '1rem',
            justifyContent: 'center',
            flexWrap: 'wrap',
            marginBottom: '2.5rem',
          }}
        >
          {session ? (
            <Link
              href="/discovery/personalized"
              className="btn btn-primary"
              style={{ padding: '0.875rem 2rem', fontSize: '1.05rem', minWidth: '180px' }}
            >
              <Sparkles size={20} /> {t('personalized_discovery_cta')}
            </Link>
          ) : (
            <Link
              href="/catalog"
              className="btn btn-primary"
              style={{ padding: '0.875rem 2rem', fontSize: '1.05rem', minWidth: '180px' }}
            >
              <Compass size={20} /> {t('browse_catalog_cta')}
            </Link>
          )}
          {session && (
            <Link
              href="/catalog"
              className="btn btn-outline"
              style={{ padding: '0.875rem 2rem', fontSize: '1.05rem', minWidth: '180px' }}
            >
              <Compass size={20} /> {t('browse_catalog_cta')}
            </Link>
          )}
          <Link
            href="/ai-discovery"
            className="btn btn-outline"
            style={{ padding: '0.875rem 2rem', fontSize: '1.05rem', minWidth: '180px' }}
          >
            <Sparkles size={20} className="text-gradient" /> {t('ai_discovery_cta')}
          </Link>
        </div>

        {/* Quick Genre Chips */}
        <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'center', flexWrap: 'wrap', alignItems: 'center' }}>
          <span style={{ fontSize: '0.85rem', color: 'var(--muted)', marginRight: '0.25rem' }}>{t('popular_genre_label')}</span>
          {POPULAR_GENRES.map(genre => (
            <Link
              key={genre}
              href={`/catalog?category=${encodeURIComponent(genre)}`}
              style={{
                fontSize: '0.8rem',
                padding: '0.3rem 0.75rem',
                borderRadius: '9999px',
                background: 'rgba(255, 255, 255, 0.05)',
                border: '1px solid var(--card-border)',
                color: 'var(--foreground)',
                transition: 'all 0.2s ease',
              }}
            >
              {translateGenre(lang, genre)}
            </Link>
          ))}
        </div>
      </div>

      {/* Today's review: the core remember-what-you-read loop comes first */}
      {session && (
        <section id="today-review" style={{ marginBottom: '3rem' }}>
          <SmartReviewWidget />
        </section>
      )}

      {/* Authenticated Taste Profile Banner / Customizer */}
      {session && (
        <HomePersonalizationBanner
          initialGenres={userPreferredGenres}
          hasPersonalizedRecs={personalizedRecs.length > 0}
          autoOpen={autoOpenOnboarding}
        />
      )}

      {/* ── 1. Picked For You (Personalized Recommendations) ───────────────── */}
      {session && personalizedRecs.length > 0 && (
        <section id="for-you" style={{ marginBottom: '4.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: '1.75rem' }}>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
                <Sparkles size={22} className="text-gradient" />
                <h2 style={{ fontSize: '2rem', margin: 0 }}>{t('picked_for_you')}</h2>
              </div>
              <p className="text-muted" style={{ margin: 0, fontSize: '0.95rem' }}>
                {t('picked_for_you_subtitle')}
              </p>
            </div>
            <Link
              href="/discovery/personalized"
              className="text-muted"
              style={{ display: 'inline-flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.9rem' }}
            >
              {t('personalized_discovery_cta')} <ArrowRight size={14} />
            </Link>
          </div>
          <div className="grid-books">
            {personalizedRecs.map((rec) => (
              <BookCard key={rec.isbn13} book={rec} />
            ))}
          </div>
        </section>
      )}

      {/* ── Reading Journey Dashboard (Prominent Reading Surface) ───────── */}
      {session && libraryItems.length > 0 && (
        <ReadingJourneyDashboard items={libraryItems} />
      )}

      {/* ── 2. Continue Your Journey (Currently Reading) ──────────────────── */}
      {session && readingBooks.length > 0 && (
        <section style={{ marginBottom: '4.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: '1.75rem' }}>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
                <BookOpen size={22} color="var(--primary)" />
                <h2 style={{ fontSize: '2rem', margin: 0 }}>{t('continue_journey')}</h2>
              </div>
              <p className="text-muted" style={{ margin: 0, fontSize: '0.95rem' }}>
                {t('continue_journey_subtitle')}
              </p>
            </div>
            <Link
              href="/favorites"
              className="text-muted"
              style={{ display: 'inline-flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.9rem' }}
            >
              {t('view_library')} <ArrowRight size={14} />
            </Link>
          </div>
          <div className="grid-books">
            {readingBooks.map((book) => (
              <BookCard key={book.isbn13} book={book} userInteraction="reading" />
            ))}
          </div>
        </section>
      )}

      {/* ── 3. Your Reading List (Want to Read) ────────────────────────────── */}
      {session && wantToReadBooks.length > 0 && (
        <section style={{ marginBottom: '4.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: '1.75rem' }}>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
                <Bookmark size={22} color="var(--accent)" />
                <h2 style={{ fontSize: '2rem', margin: 0 }}>{t('your_reading_list')}</h2>
              </div>
              <p className="text-muted" style={{ margin: 0, fontSize: '0.95rem' }}>
                {t('your_reading_list_subtitle')}
              </p>
            </div>
            <Link
              href="/favorites"
              className="text-muted"
              style={{ display: 'inline-flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.9rem' }}
            >
              {t('manage_shelf')} <ArrowRight size={14} />
            </Link>
          </div>
          <div className="grid-books">
            {wantToReadBooks.map((book) => (
              <BookCard key={book.isbn13} book={book} userInteraction="want_to_read" />
            ))}
          </div>
        </section>
      )}

      {/* ── 4. Because You Enjoy {primaryGenre} ───────────────────────────── */}
      {session && becauseYouEnjoyBooks.length > 0 && primaryGenre && (
        <section style={{ marginBottom: '4.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: '1.75rem' }}>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
                <Compass size={22} color="var(--primary)" />
                <h2 style={{ fontSize: '2rem', margin: 0 }}>{t('because_you_enjoy', { genre: primaryGenre })}</h2>
              </div>
              <p className="text-muted" style={{ margin: 0, fontSize: '0.95rem' }}>
                {t('because_you_enjoy_subtitle')}
              </p>
            </div>
            <Link
              href={`/catalog?category=${encodeURIComponent(primaryGenre)}`}
              className="text-muted"
              style={{ display: 'inline-flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.9rem' }}
            >
              {t('explore_genre', { genre: primaryGenre })} <ArrowRight size={14} />
            </Link>
          </div>
          <div className="grid-books">
            {becauseYouEnjoyBooks.map((book) => (
              <BookCard key={book.isbn13} book={book} />
            ))}
          </div>
        </section>
      )}

      {/* ── 5. Popular Discoveries (Trending in the Catalog) ───────────────── */}
      {featuredBooks.length > 0 && (
        <section style={{ marginBottom: '4.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: '1.75rem' }}>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
                <TrendingUp size={22} color="var(--primary)" />
                <h2 style={{ fontSize: '2rem', margin: 0 }}>{t('popular_discoveries')}</h2>
              </div>
              <p className="text-muted" style={{ margin: 0, fontSize: '0.95rem' }}>
                {t('popular_discoveries_subtitle')}
              </p>
            </div>
            <Link
              href="/catalog?sort=popularity"
              className="text-muted"
              style={{ display: 'inline-flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.9rem' }}
            >
              {t('view_more')} <ArrowRight size={14} />
            </Link>
          </div>
          <div className="grid-books">
            {featuredBooks.map((book) => (
              <BookCard key={book.isbn13} book={book} />
            ))}
          </div>
        </section>
      )}

      {/* 3-Pillar Feature Grid */}
      <section style={{ marginTop: '2rem' }}>
        <div style={{ textAlign: 'center', marginBottom: '2.5rem' }}>
          <h2 style={{ fontSize: '2rem', marginBottom: '0.5rem' }}>{t('home_features_title')}</h2>
          <p className="text-muted" style={{ maxWidth: '580px', margin: '0 auto' }}>
            {t('home_features_subtitle')}
          </p>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '1.75rem' }}>
          <div className="glass-panel" style={{ padding: '2rem' }}>
            <div
              style={{
                background: 'rgba(99, 102, 241, 0.12)',
                width: '52px',
                height: '52px',
                borderRadius: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                marginBottom: '1.25rem',
              }}
            >
              <BookOpen size={26} color="var(--primary)" />
            </div>
            <h3 style={{ fontSize: '1.3rem', marginBottom: '0.5rem' }}>{t('home_feature_catalog')}</h3>
            <p className="text-muted" style={{ lineHeight: '1.6', fontSize: '0.95rem' }}>
              {t('home_feature_catalog_desc')}
            </p>
          </div>
          
          <div className="glass-panel" style={{ padding: '2rem' }}>
            <div
              style={{
                background: 'rgba(139, 92, 246, 0.12)',
                width: '52px',
                height: '52px',
                borderRadius: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                marginBottom: '1.25rem',
              }}
            >
              <Sparkles size={26} color="var(--accent)" />
            </div>
            <h3 style={{ fontSize: '1.3rem', marginBottom: '0.5rem' }}>{t('home_feature_ai')}</h3>
            <p className="text-muted" style={{ lineHeight: '1.6', fontSize: '0.95rem' }}>
              {t('home_feature_ai_desc')}
            </p>
          </div>

          <div className="glass-panel" style={{ padding: '2rem' }}>
            <div
              style={{
                background: 'rgba(16, 185, 129, 0.12)',
                width: '52px',
                height: '52px',
                borderRadius: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                marginBottom: '1.25rem',
              }}
            >
              <Library size={26} color="var(--success)" />
            </div>
            <h3 style={{ fontSize: '1.3rem', marginBottom: '0.5rem' }}>{t('home_feature_library')}</h3>
            <p className="text-muted" style={{ lineHeight: '1.6', fontSize: '0.95rem' }}>
              {t('home_feature_library_desc')}
            </p>
          </div>
        </div>
      </section>
    </div>
  );
}
