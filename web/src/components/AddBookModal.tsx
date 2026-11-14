'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { BookPlus, Loader2, PenLine, Search, X } from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import { addCatalogBookAction, lookupBooksAction } from '@/app/actions/catalog';
import { translateGenre } from '@/lib/i18n';
import { CANONICAL_GENRES } from '@/lib/genres';
import type { BookLookupResult, NewCatalogBook } from '@/types';

const EMPTY: NewCatalogBook = { title: '', authors: '', categories: '', isbn13: '', pageCount: 0, publishedDate: '', description: '', thumbnail: '' };

/** Picks the canonical genre that best matches free-text categories from Google Books / Open Library. */
export function guessGenre(raw: string): string {
  const text = (raw || '').toLowerCase();
  if (!text) return '';
  const exact = CANONICAL_GENRES.find((g) => text.includes(g.toLowerCase()));
  if (exact) return exact;
  const firstWord = CANONICAL_GENRES.find((g) => text.includes(g.toLowerCase().split(/[ &]/)[0]));
  return firstWord || '';
}

interface AddBookModalProps {
  open: boolean;
  onClose: () => void;
  initialQuery?: string;
}

export function AddBookModal({ open, onClose, initialQuery = '' }: AddBookModalProps) {
  const { t, preferences } = usePreferences();
  const router = useRouter();
  const [query, setQuery] = useState(initialQuery);
  const [results, setResults] = useState<BookLookupResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [form, setForm] = useState<NewCatalogBook | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) return;
    inputRef.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  // Debounced lookup while the reader types.
  useEffect(() => {
    const q = query.trim();
    if (!open || form || q.length < 2) return;
    let cancelled = false;
    const timer = setTimeout(async () => {
      setSearching(true);
      const res = await lookupBooksAction(q);
      if (cancelled) return;
      setSearching(false);
      setResults(res.success ? res.results : []);
      setError(res.success ? null : t('add_book_lookup_error'));
    }, 400);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query, open, form, t]);

  if (!open) return null;

  // Short queries never hit the network; hide stale results instead of resetting state.
  const visibleResults = query.trim().length >= 2 ? results : [];

  const pick = (r: BookLookupResult) => {
    if (r.inCatalogIsbn) {
      onClose();
      router.push(`/book/${encodeURIComponent(r.inCatalogIsbn)}`);
      return;
    }
    setForm({
      title: r.title,
      authors: r.authors,
      categories: guessGenre(r.categories),
      isbn13: r.isbn13,
      pageCount: r.pageCount,
      publishedDate: r.publishedDate,
      description: r.description,
      thumbnail: r.thumbnail,
    });
  };

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form) return;
    setSaving(true);
    setError(null);
    const res = await addCatalogBookAction(form);
    setSaving(false);
    if (!res.success || !res.isbn13) {
      setError(res.error || t('add_book_save_error'));
      return;
    }
    onClose();
    router.push(`/book/${encodeURIComponent(res.isbn13)}`);
  };

  const field = (key: keyof NewCatalogBook, value: string | number) => setForm((f) => (f ? { ...f, [key]: value } : f));
  const inputStyle: React.CSSProperties = { width: '100%', padding: '0.6rem 0.75rem', borderRadius: '10px', border: '1px solid var(--card-border)', background: 'var(--surface-subtle)', color: 'var(--text-primary)', fontSize: '0.95rem' };
  const labelStyle: React.CSSProperties = { display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: '0.3rem' };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-book-title"
      data-testid="add-book-modal"
      onClick={(e) => e.target === e.currentTarget && onClose()}
      style={{ position: 'fixed', inset: 0, zIndex: 100, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'flex-start', justifyContent: 'center', padding: '5vh 1rem', overflowY: 'auto' }}
    >
      <div className="glass-panel animate-fade-in" style={{ width: '100%', maxWidth: '560px', padding: '1.5rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '1rem', marginBottom: '0.5rem' }}>
          <h2 id="add-book-title" style={{ fontSize: '1.35rem', margin: 0, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <BookPlus size={20} aria-hidden="true" style={{ color: 'var(--primary)' }} />
            {t('add_book_title')}
          </h2>
          <button type="button" onClick={onClose} aria-label={t('recall_card_dismiss')} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
            <X size={20} aria-hidden="true" />
          </button>
        </div>
        <p className="text-muted" style={{ fontSize: '0.9rem', marginBottom: '1rem' }}>{t('add_book_subtitle')}</p>

        {!form ? (
          <>
            <div style={{ position: 'relative' }}>
              <Search size={16} aria-hidden="true" style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
              <input
                ref={inputRef}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={t('add_book_search_placeholder')}
                aria-label={t('add_book_search_placeholder')}
                style={{ ...inputStyle, paddingLeft: '2.25rem' }}
              />
            </div>
            <ul aria-live="polite" style={{ listStyle: 'none', margin: '0.75rem 0', padding: 0, display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
              {searching && (
                <li className="text-muted" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.9rem' }}>
                  <Loader2 size={16} className="animate-spin" aria-hidden="true" /> {t('loading')}
                </li>
              )}
              {!searching && visibleResults.map((r, i) => (
                <li key={`${r.isbn13}-${i}`}>
                  <button
                    type="button"
                    onClick={() => pick(r)}
                    style={{ width: '100%', display: 'flex', gap: '0.75rem', alignItems: 'center', textAlign: 'left', padding: '0.5rem', borderRadius: '10px', border: '1px solid var(--card-border)', background: 'transparent', color: 'inherit', cursor: 'pointer' }}
                  >
                    {r.thumbnail ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={r.thumbnail} alt="" width={36} height={54} style={{ borderRadius: '4px', objectFit: 'cover', flexShrink: 0 }} />
                    ) : (
                      <span aria-hidden="true" style={{ width: 36, height: 54, borderRadius: '4px', background: 'var(--surface-subtle)', flexShrink: 0 }} />
                    )}
                    <span style={{ minWidth: 0, flex: 1 }}>
                      <span style={{ display: 'block', fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.title}</span>
                      <span className="text-muted" style={{ display: 'block', fontSize: '0.8rem' }}>
                        {[r.authors, r.publishedDate].filter(Boolean).join(' · ')}
                      </span>
                    </span>
                    <span style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--primary)', whiteSpace: 'nowrap' }}>
                      {r.inCatalogIsbn ? t('add_book_open_existing') : t('add_book_select')}
                    </span>
                  </button>
                </li>
              ))}
              {!searching && query.trim().length >= 2 && visibleResults.length === 0 && !error && (
                <li className="text-muted" style={{ fontSize: '0.9rem' }}>{t('add_book_no_results')}</li>
              )}
            </ul>
            <button type="button" className="btn btn-outline" onClick={() => setForm({ ...EMPTY, title: query.trim() })} style={{ gap: '0.4rem' }}>
              <PenLine size={16} aria-hidden="true" /> {t('add_book_manual')}
            </button>
          </>
        ) : (
          <form onSubmit={save} style={{ display: 'grid', gap: '0.8rem' }}>
            <div>
              <label style={labelStyle} htmlFor="ab-title">{t('add_book_field_title')} *</label>
              <input id="ab-title" required maxLength={300} value={form.title} onChange={(e) => field('title', e.target.value)} style={inputStyle} />
            </div>
            <div>
              <label style={labelStyle} htmlFor="ab-authors">{t('add_book_field_authors')} *</label>
              <input id="ab-authors" required maxLength={300} value={form.authors} onChange={(e) => field('authors', e.target.value)} style={inputStyle} />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: '0.8rem' }}>
              <div>
                <label style={labelStyle} htmlFor="ab-genre">{t('add_book_field_genre')}</label>
                <select id="ab-genre" value={form.categories} onChange={(e) => field('categories', e.target.value)} style={inputStyle}>
                  <option value="">—</option>
                  {CANONICAL_GENRES.map((g) => (
                    <option key={g} value={g}>{translateGenre(preferences.language, g)}</option>
                  ))}
                </select>
              </div>
              <div>
                <label style={labelStyle} htmlFor="ab-year">{t('add_book_field_year')}</label>
                <input id="ab-year" inputMode="numeric" maxLength={4} value={form.publishedDate} onChange={(e) => field('publishedDate', e.target.value.replace(/\D/g, ''))} style={inputStyle} />
              </div>
              <div>
                <label style={labelStyle} htmlFor="ab-pages">{t('add_book_field_pages')}</label>
                <input id="ab-pages" type="number" min={0} max={20000} value={form.pageCount || ''} onChange={(e) => field('pageCount', Number(e.target.value) || 0)} style={inputStyle} />
              </div>
            </div>
            <div>
              <label style={labelStyle} htmlFor="ab-isbn">ISBN</label>
              <input id="ab-isbn" inputMode="numeric" maxLength={17} placeholder="978…" value={form.isbn13} onChange={(e) => field('isbn13', e.target.value)} style={inputStyle} />
            </div>
            {error && <p role="alert" style={{ color: 'var(--danger)', fontSize: '0.9rem', margin: 0 }}>{error}</p>}
            <div style={{ display: 'flex', gap: '0.6rem', justifyContent: 'flex-end', flexWrap: 'wrap' }}>
              <button type="button" className="btn btn-outline" onClick={() => setForm(null)}>{t('add_book_back')}</button>
              <button type="submit" className="btn btn-primary" disabled={saving} style={{ gap: '0.4rem' }}>
                {saving && <Loader2 size={16} className="animate-spin" aria-hidden="true" />}
                {t('add_book_save')}
              </button>
            </div>
            <p className="text-muted" style={{ fontSize: '0.78rem', margin: 0 }}>{t('add_book_privacy_note')}</p>
          </form>
        )}
        {!form && error && <p role="alert" style={{ color: 'var(--danger)', fontSize: '0.9rem', marginTop: '0.75rem' }}>{error}</p>}
      </div>
    </div>
  );
}
