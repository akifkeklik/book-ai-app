'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { usePreferences } from '@/components/PreferencesProvider';
import { useAuth } from '@/components/AuthProvider';
import { LANGUAGES, LANGUAGE_NAMES, type ThemeMode, type ColorPalette, type FontFamily, type FontScale, type LineSpacing, type Language } from '@/lib/preferences';
import {
  Sun,
  Moon,
  Laptop,
  Palette,
  Type,
  Check,
  Sliders,
  RotateCcw,
  Sparkles,
  BookOpen,
  User,
  ShieldCheck,
  Globe,
  Star,
  Heart,
  Bookmark,
  Compass,
  Loader2,
} from 'lucide-react';
import Link from 'next/link';
import { AVAILABLE_GENRES } from '@/components/TasteProfileModal';
import { getUserPreferencesAction, updateUserPreferencesAction } from '@/app/actions/user';
import { translateGenre } from '@/lib/i18n';

interface PaletteOption {
  id: ColorPalette;
  nameKey:
    | 'palette_ocean_blue'
    | 'palette_forest_green'
    | 'palette_lavender'
    | 'palette_terracotta'
    | 'palette_amber'
    | 'palette_turquoise';
  accentHex: string;
  darkBg: string;
  lightBg: string;
}

const PALETTES: PaletteOption[] = [
  { id: 'ocean_blue', nameKey: 'palette_ocean_blue', accentHex: '#0284c7', darkBg: '#0c1929', lightBg: '#f0f7ff' },
  { id: 'forest_green', nameKey: 'palette_forest_green', accentHex: '#059669', darkBg: '#0e1c14', lightBg: '#f0f8f4' },
  { id: 'lavender', nameKey: 'palette_lavender', accentHex: '#7c3aed', darkBg: '#161329', lightBg: '#f7f5fc' },
  { id: 'terracotta', nameKey: 'palette_terracotta', accentHex: '#c2410c', darkBg: '#221611', lightBg: '#fdf6f0' },
  { id: 'amber', nameKey: 'palette_amber', accentHex: '#d97706', darkBg: '#1c1608', lightBg: '#fffdf5' },
  { id: 'turquoise', nameKey: 'palette_turquoise', accentHex: '#0d9488', darkBg: '#091b1a', lightBg: '#f0fdfa' },
];

export default function SettingsPage() {
  const {
    preferences,
    setThemeMode,
    setColorPalette,
    setFontFamily,
    setFontScale,
    setLineSpacing,
    setHighContrast,
    setReducedMotion,
    setLanguage,
    setDensity,
    resetToDefaults,
    t,
  } = usePreferences();

  const router = useRouter();
  const { user } = useAuth();
  const [genres, setGenres] = useState<string[]>([]);
  const [isLoadingGenres, setIsLoadingGenres] = useState(Boolean(user));
  const [isSavingGenres, setIsSavingGenres] = useState(false);
  const [genreSaveSuccess, setGenreSaveSuccess] = useState(false);
  const [genreError, setGenreError] = useState<string | null>(null);

  useEffect(() => {
    let ignore = false;
    if (user) {
      getUserPreferencesAction()
        .then((res) => {
          if (!ignore && res.success) {
            setGenres(res.preferredGenres);
          }
        })
        .finally(() => {
          if (!ignore) setIsLoadingGenres(false);
        });
    }
    return () => {
      ignore = true;
    };
  }, [user]);

  const toggleGenre = (genre: string) => {
    setGenres((prev) =>
      prev.includes(genre) ? prev.filter((g) => g !== genre) : [...prev, genre]
    );
    setGenreSaveSuccess(false);
  };

  const handleSaveGenres = async () => {
    setIsSavingGenres(true);
    setGenreError(null);
    setGenreSaveSuccess(false);
    try {
      const res = await updateUserPreferencesAction(genres);
      if (res.success) {
        setGenreSaveSuccess(true);
        router.refresh();
      } else {
        setGenreError(res.error || 'Failed to update taste profile');
      }
    } catch (err) {
      setGenreError(err instanceof Error ? err.message : 'Error updating preferences');
    } finally {
      setIsSavingGenres(false);
    }
  };

  return (
    <div className="container animate-fade-in" style={{ maxWidth: '920px', paddingBottom: '5rem' }}>
      {/* Header */}
      <div style={{ marginBottom: '2.5rem', textAlign: 'center' }}>
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.5rem',
            padding: '0.4rem 1rem',
            borderRadius: '9999px',
            background: 'rgba(99, 102, 241, 0.1)',
            border: '1px solid var(--card-border)',
            marginBottom: '1rem',
            fontSize: '0.85rem',
            fontWeight: 600,
            color: 'var(--primary)',
          }}
        >
          <Sliders size={15} />
          <span>{t('nav_profile_settings')}</span>
        </div>
        <h1 style={{ fontSize: '2.5rem', marginBottom: '0.5rem' }}>{t('settings_title')}</h1>
        <p className="text-muted" style={{ maxWidth: '600px', margin: '0 auto' }}>
          {t('settings_subtitle')}
        </p>
      </div>

      {/* ── Live Interactive Preview Card ─────────────────────────────────── */}
      <div
        className="glass-panel"
        style={{
          marginBottom: '3rem',
          border: preferences.highContrast ? '2px solid var(--border)' : '1px solid var(--card-border)',
          background: 'var(--card)',
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
            <Sparkles size={18} color="var(--primary)" />
            <span style={{ fontSize: '0.85rem', fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--primary)' }}>
              {t('live_preview')}
            </span>
          </div>
          <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
            <span className="status-badge status-badge-reading">
              <Bookmark size={12} /> {t('status_reading')}
            </span>
            <span className="status-badge status-badge-favorite">
              <Heart size={12} fill="var(--status-favorite)" /> {t('status_favorite')}
            </span>
          </div>
        </div>

        <div style={{ display: 'flex', gap: '1.5rem', alignItems: 'flex-start', flexWrap: 'wrap' }}>
          <div
            style={{
              width: '100px',
              height: '150px',
              borderRadius: '8px',
              background: 'linear-gradient(135deg, var(--primary), var(--accent))',
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'center',
              alignItems: 'center',
              color: '#ffffff',
              boxShadow: '0 8px 24px rgba(0,0,0,0.3)',
              padding: '0.75rem',
              textAlign: 'center',
              flexShrink: 0,
            }}
          >
            <BookOpen size={28} style={{ marginBottom: '0.5rem' }} />
            <span style={{ fontSize: '0.7rem', fontWeight: 700, lineHeight: 1.2 }}>LIBRIS EDITORIAL</span>
          </div>

          <div style={{ flex: 1, minWidth: '260px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', marginBottom: '0.4rem' }}>
              <div style={{ display: 'flex', color: 'var(--rating)' }}>
                {[...Array(5)].map((_, i) => (
                  <Star key={i} size={14} fill="var(--rating)" />
                ))}
              </div>
              <span style={{ fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-muted)' }}>{t('settings_preview_rating')}</span>
            </div>

            <h3 style={{ fontSize: '1.4rem', marginBottom: '0.25rem', color: 'var(--text-primary)' }}>
              {t('preview_book_title')}
            </h3>
            <p className="text-muted" style={{ fontSize: '0.9rem', marginBottom: '0.85rem' }}>
              {t('preview_book_author')}
            </p>

            <blockquote
              style={{
                fontStyle: 'italic',
                paddingLeft: '1rem',
                borderLeft: '3px solid var(--primary)',
                color: 'var(--text-secondary)',
                fontSize: '0.95rem',
              }}
            >
              {t('preview_quote')}
            </blockquote>
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '2.5rem' }}>
        {/* ── Section: Appearance ─────────────────────────────────────────── */}
        <section className="glass-panel" style={{ padding: '2rem' }}>
          <h2 style={{ fontSize: '1.4rem', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
            <Palette size={20} color="var(--primary)" />
            <span>{t('tab_appearance')}</span>
          </h2>
          <p className="text-muted" style={{ fontSize: '0.9rem', marginBottom: '1.75rem' }}>
            {t('settings_appearance_desc')}
          </p>

          {/* Theme Mode Segmented Controls */}
          <div style={{ marginBottom: '2rem' }}>
            <label className="input-label" style={{ marginBottom: '0.75rem', display: 'block' }}>
              {t('theme_mode')}
            </label>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: '0.75rem' }}>
              {[
                { id: 'light' as ThemeMode, label: t('theme_light'), icon: Sun },
                { id: 'dark' as ThemeMode, label: t('theme_dark'), icon: Moon },
                { id: 'system' as ThemeMode, label: t('theme_system'), icon: Laptop },
              ].map((item) => {
                const IconComp = item.icon;
                const isSelected = preferences.themeMode === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setThemeMode(item.id)}
                    className="library-tab-btn"
                    style={{
                      justifyContent: 'center',
                      padding: '0.85rem 1rem',
                      borderColor: isSelected ? 'var(--primary)' : 'var(--card-border)',
                      background: isSelected ? 'rgba(99, 102, 241, 0.15)' : 'var(--surface-subtle)',
                      color: isSelected ? 'var(--primary)' : 'var(--text-muted)',
                      fontWeight: isSelected ? 700 : 500,
                    }}
                  >
                    <IconComp size={16} />
                    <span>{item.label}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* 6 Pastel Palettes */}
          <div style={{ marginBottom: '2rem' }}>
            <label className="input-label" style={{ marginBottom: '0.75rem', display: 'block' }}>
              {t('color_palette')}
            </label>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '0.85rem' }}>
              {PALETTES.map((pal) => {
                const isSelected =
                  preferences.colorPalette === pal.id ||
                  (pal.id === 'ocean_blue' && (preferences.colorPalette === 'powder_blue' || preferences.colorPalette === 'editorial')) ||
                  (pal.id === 'forest_green' && preferences.colorPalette === 'sage') ||
                  (pal.id === 'terracotta' && preferences.colorPalette === 'peach');
                return (
                  <button
                    key={pal.id}
                    type="button"
                    onClick={() => setColorPalette(pal.id)}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: '0.85rem',
                      padding: '0.85rem 1rem',
                      borderRadius: '12px',
                      background: isSelected ? 'rgba(99, 102, 241, 0.12)' : 'var(--surface-subtle)',
                      border: `1.5px solid ${isSelected ? pal.accentHex : 'var(--card-border)'}`,
                      cursor: 'pointer',
                      textAlign: 'left',
                      transition: 'all 0.2s ease',
                    }}
                  >
                    <div
                      style={{
                        width: '28px',
                        height: '28px',
                        borderRadius: '50%',
                        background: pal.accentHex,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        boxShadow: `0 0 10px ${pal.accentHex}66`,
                        flexShrink: 0,
                      }}
                    >
                      {isSelected && <Check size={16} color="#ffffff" strokeWidth={3} />}
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontSize: '0.9rem', fontWeight: isSelected ? 700 : 500, color: 'var(--text-primary)' }}>
                        {t(pal.nameKey)}
                      </div>
                      <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                        {pal.id}
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Toggles: High Contrast & Reduced Motion & Density */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '1rem', borderTop: '1px solid var(--divider)', paddingTop: '1.5rem' }}>
            {/* High Contrast */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0.5rem 0' }}>
              <div>
                <div style={{ fontWeight: 600, fontSize: '0.95rem' }}>{t('high_contrast')}</div>
                <div className="text-muted" style={{ fontSize: '0.8rem' }}>{t('high_contrast_desc')}</div>
              </div>
              <input
                type="checkbox"
                checked={preferences.highContrast}
                onChange={(e) => setHighContrast(e.target.checked)}
                style={{ width: '20px', height: '20px', accentColor: 'var(--primary)', cursor: 'pointer' }}
                aria-label={t('high_contrast')}
              />
            </div>

            {/* Reduced Motion */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0.5rem 0' }}>
              <div>
                <div style={{ fontWeight: 600, fontSize: '0.95rem' }}>{t('reduced_motion')}</div>
                <div className="text-muted" style={{ fontSize: '0.8rem' }}>{t('reduced_motion_desc')}</div>
              </div>
              <input
                type="checkbox"
                checked={preferences.reducedMotion}
                onChange={(e) => setReducedMotion(e.target.checked)}
                style={{ width: '20px', height: '20px', accentColor: 'var(--primary)', cursor: 'pointer' }}
                aria-label={t('reduced_motion')}
              />
            </div>

            {/* Density Selector */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0.5rem 0' }}>
              <div>
                <div style={{ fontWeight: 600, fontSize: '0.95rem' }}>{t('density')}</div>
                <div className="text-muted" style={{ fontSize: '0.8rem' }}>
                  {preferences.density === 'comfortable' ? t('density_comfortable') : t('density_compact')}
                </div>
              </div>
              <div style={{ display: 'flex', gap: '0.4rem' }}>
                <button
                  type="button"
                  onClick={() => setDensity('comfortable')}
                  className="library-tab-btn"
                  style={{
                    padding: '0.4rem 0.8rem',
                    fontSize: '0.8rem',
                    background: preferences.density === 'comfortable' ? 'rgba(99, 102, 241, 0.2)' : 'transparent',
                    borderColor: preferences.density === 'comfortable' ? 'var(--primary)' : 'var(--card-border)',
                  }}
                >
                  {t('density_comfortable')}
                </button>
                <button
                  type="button"
                  onClick={() => setDensity('compact')}
                  className="library-tab-btn"
                  style={{
                    padding: '0.4rem 0.8rem',
                    fontSize: '0.8rem',
                    background: preferences.density === 'compact' ? 'rgba(99, 102, 241, 0.2)' : 'transparent',
                    borderColor: preferences.density === 'compact' ? 'var(--primary)' : 'var(--card-border)',
                  }}
                >
                  {t('density_compact')}
                </button>
              </div>
            </div>
          </div>
        </section>

        {/* ── Section: Readability & Typography ───────────────────────────── */}
        <section className="glass-panel" style={{ padding: '2rem' }}>
          <h2 style={{ fontSize: '1.4rem', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
            <Type size={20} color="var(--primary)" />
            <span>{t('tab_readability')}</span>
          </h2>
          <p className="text-muted" style={{ fontSize: '0.9rem', marginBottom: '1.75rem' }}>
            {t('settings_readability_desc')}
          </p>

          {/* Font Family */}
          <div style={{ marginBottom: '1.75rem' }}>
            <label className="input-label" style={{ marginBottom: '0.75rem', display: 'block' }}>
              {t('font_family')}
            </label>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '0.75rem' }}>
              {[
                { id: 'serif' as FontFamily, label: t('font_serif'), style: { fontFamily: 'var(--font-editorial)' } },
                { id: 'sans' as FontFamily, label: t('font_sans'), style: { fontFamily: 'var(--font-body)' } },
                { id: 'mono' as FontFamily, label: t('font_mono'), style: { fontFamily: 'var(--font-mono)' } },
              ].map((item) => {
                const isSelected = preferences.fontFamily === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setFontFamily(item.id)}
                    className="library-tab-btn"
                    style={{
                      justifyContent: 'center',
                      padding: '0.85rem 1rem',
                      borderColor: isSelected ? 'var(--primary)' : 'var(--card-border)',
                      background: isSelected ? 'rgba(99, 102, 241, 0.15)' : 'var(--surface-subtle)',
                      color: isSelected ? 'var(--primary)' : 'var(--text-muted)',
                      fontWeight: isSelected ? 700 : 500,
                      ...item.style,
                    }}
                  >
                    <span>{item.label}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Typographic Scale */}
          <div style={{ marginBottom: '1.75rem' }}>
            <label className="input-label" style={{ marginBottom: '0.75rem', display: 'block' }}>
              {t('font_scale')}
            </label>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))', gap: '0.75rem' }}>
              {[
                { scale: 0.9 as FontScale, label: t('scale_small') },
                { scale: 1.0 as FontScale, label: t('scale_default') },
                { scale: 1.15 as FontScale, label: t('scale_large') },
                { scale: 1.3 as FontScale, label: t('scale_xl') },
              ].map((item) => {
                const isSelected = preferences.fontScale === item.scale;
                return (
                  <button
                    key={item.scale}
                    type="button"
                    onClick={() => setFontScale(item.scale)}
                    className="library-tab-btn"
                    style={{
                      justifyContent: 'center',
                      padding: '0.75rem 1rem',
                      borderColor: isSelected ? 'var(--primary)' : 'var(--card-border)',
                      background: isSelected ? 'rgba(99, 102, 241, 0.15)' : 'var(--surface-subtle)',
                      color: isSelected ? 'var(--primary)' : 'var(--text-muted)',
                      fontWeight: isSelected ? 700 : 500,
                    }}
                  >
                    <span>{item.label}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Line Spacing */}
          <div>
            <label className="input-label" style={{ marginBottom: '0.75rem', display: 'block' }}>
              {t('line_spacing')}
            </label>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '0.75rem' }}>
              {[
                { spacing: 'normal' as LineSpacing, label: t('spacing_normal') },
                { spacing: 'relaxed' as LineSpacing, label: t('spacing_relaxed') },
              ].map((item) => {
                const isSelected = preferences.lineSpacing === item.spacing;
                return (
                  <button
                    key={item.spacing}
                    type="button"
                    onClick={() => setLineSpacing(item.spacing)}
                    className="library-tab-btn"
                    style={{
                      justifyContent: 'center',
                      padding: '0.75rem 1rem',
                      borderColor: isSelected ? 'var(--primary)' : 'var(--card-border)',
                      background: isSelected ? 'rgba(99, 102, 241, 0.15)' : 'var(--surface-subtle)',
                      color: isSelected ? 'var(--primary)' : 'var(--text-muted)',
                      fontWeight: isSelected ? 700 : 500,
                    }}
                  >
                    <span>{item.label}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </section>

        {/* ── Section: Language & Region ──────────────────────────────────── */}
        <section className="glass-panel" style={{ padding: '2rem' }}>
          <h2 style={{ fontSize: '1.4rem', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
            <Globe size={20} color="var(--primary)" />
            <span>{t('tab_language')}</span>
          </h2>
          <p className="text-muted" style={{ fontSize: '0.9rem', marginBottom: '1.75rem' }}>
            {t('settings_language_desc')}
          </p>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: '0.85rem' }}>
            {LANGUAGES.map((code) => ({ id: code as Language, label: LANGUAGE_NAMES[code], native: code.toUpperCase() })).map((lang) => {
              const isSelected = preferences.language === lang.id;
              return (
                <button
                  key={lang.id}
                  type="button"
                  onClick={() => setLanguage(lang.id)}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '1rem 1.25rem',
                    borderRadius: '12px',
                    background: isSelected ? 'rgba(99, 102, 241, 0.15)' : 'var(--surface-subtle)',
                    border: `1.5px solid ${isSelected ? 'var(--primary)' : 'var(--card-border)'}`,
                    cursor: 'pointer',
                    color: isSelected ? 'var(--primary)' : 'var(--text-primary)',
                    fontWeight: isSelected ? 700 : 500,
                  }}
                >
                  <div style={{ textAlign: 'left' }}>
                    <div style={{ fontSize: '1rem', fontWeight: 600 }}>{lang.label}</div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>{lang.native}</div>
                  </div>
                  {isSelected && <Check size={18} />}
                </button>
              );
            })}
          </div>
        </section>

        {/* ── Section: Reading Taste Profile ─────────────────────────────── */}
        <section className="glass-panel" style={{ padding: '2rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '1rem', marginBottom: '1rem' }}>
            <div>
              <h2 style={{ fontSize: '1.4rem', marginBottom: '0.4rem', display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
                <Compass size={20} color="var(--primary)" />
                <span>{t('taste_profile_title')}</span>
              </h2>
              <p className="text-muted" style={{ fontSize: '0.9rem', margin: 0, maxWidth: '580px' }}>
                {t('taste_profile_subtitle')}
              </p>
            </div>
            {user && (
              <button
                type="button"
                onClick={handleSaveGenres}
                disabled={isSavingGenres || isLoadingGenres}
                className="btn btn-primary"
                style={{
                  padding: '0.6rem 1.4rem',
                  fontSize: '0.875rem',
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: '0.45rem',
                }}
              >
                {isSavingGenres ? <Loader2 size={15} className="animate-spin" /> : <Check size={15} />}
                <span>{t('taste_profile_save_btn')}</span>
              </button>
            )}
          </div>

          {!user && (
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '0.75rem',
                padding: '0.85rem 1.15rem',
                borderRadius: '12px',
                background: 'rgba(99, 102, 241, 0.08)',
                border: '1px solid var(--card-border)',
                marginBottom: '1.25rem',
                flexWrap: 'wrap',
                justifyContent: 'space-between',
              }}
            >
              <span style={{ fontSize: '0.875rem', color: 'var(--text-muted)' }}>
                {t('not_signed_in')}
              </span>
              <div style={{ display: 'flex', gap: '0.5rem' }}>
                <Link
                  href="/login?redirect=/settings"
                  className="btn btn-outline"
                  style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem' }}
                >
                  {t('nav_login')}
                </Link>
                <Link
                  href="/signup?redirect=/settings"
                  className="btn btn-primary"
                  style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem' }}
                >
                  {t('nav_signup')}
                </Link>
              </div>
            </div>
          )}

          {genreSaveSuccess && (
            <div
              role="status"
              style={{
                padding: '0.75rem 1rem',
                borderRadius: '10px',
                backgroundColor: 'rgba(16, 185, 129, 0.1)',
                border: '1px solid rgba(16, 185, 129, 0.3)',
                color: '#10b981',
                fontSize: '0.85rem',
                marginBottom: '1.25rem',
                display: 'flex',
                alignItems: 'center',
                gap: '0.5rem',
              }}
            >
              <Check size={16} />
              <span>{t('taste_profile_saved')}</span>
            </div>
          )}

          {genreError && (
            <div
              role="alert"
              style={{
                padding: '0.75rem 1rem',
                borderRadius: '10px',
                backgroundColor: 'rgba(239, 68, 68, 0.1)',
                border: '1px solid rgba(239, 68, 68, 0.3)',
                color: '#ef4444',
                fontSize: '0.85rem',
                marginBottom: '1.25rem',
              }}
            >
              {genreError}
            </div>
          )}

          {isLoadingGenres ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', padding: '1.5rem', color: 'var(--text-muted)' }}>
              <Loader2 size={18} className="animate-spin" />
              <span>{t('loading')}</span>
            </div>
          ) : (
            <div>
              <div
                style={{
                  display: 'flex',
                  flexWrap: 'wrap',
                  gap: '0.65rem',
                  marginTop: '0.5rem',
                  marginBottom: '1rem',
                }}
              >
                {AVAILABLE_GENRES.map((genre) => {
                  const isSelected = genres.includes(genre);
                  return (
                    <button
                      key={genre}
                      type="button"
                      onClick={() => toggleGenre(genre)}
                      aria-pressed={isSelected}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '0.4rem',
                        padding: '0.55rem 1.05rem',
                        borderRadius: '9999px',
                        fontSize: '0.85rem',
                        fontWeight: isSelected ? 700 : 500,
                        cursor: 'pointer',
                        border: `1.5px solid ${isSelected ? 'var(--primary)' : 'var(--card-border)'}`,
                        background: isSelected ? 'rgba(99, 102, 241, 0.18)' : 'var(--surface-subtle)',
                        color: isSelected ? 'var(--primary)' : 'var(--text-primary)',
                        transition: 'all 0.15s ease',
                      }}
                    >
                      {isSelected ? <Check size={13} /> : null}
                      <span>{translateGenre(preferences.language, genre)}</span>
                    </button>
                  );
                })}
              </div>
              <p className="text-muted" style={{ fontSize: '0.825rem', margin: 0 }}>
                {genres.length > 0
                  ? t('genres_selected_count', { count: genres.length })
                  : t('select_min_genres_hint')}
              </p>
            </div>
          )}
        </section>

        {/* ── Section: Account & Privacy ──────────────────────────────────── */}
        <section className="glass-panel" style={{ padding: '2rem' }}>
          <h2 style={{ fontSize: '1.4rem', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
            <User size={20} color="var(--primary)" />
            <span>{t('tab_account')}</span>
          </h2>
          <div style={{ marginTop: '1rem', display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap' }}>
            <div
              style={{
                width: '48px',
                height: '48px',
                borderRadius: '50%',
                background: 'var(--surface-elevated)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'var(--primary)',
              }}
            >
              <ShieldCheck size={24} />
            </div>
            <div style={{ flex: 1, minWidth: '220px' }}>
              <div style={{ fontWeight: 600, fontSize: '1rem' }}>
                {user ? user.email : 'Anonymous Guest'}
              </div>
              <div className="text-muted" style={{ fontSize: '0.85rem' }}>
                {user ? t('account_status') : t('not_signed_in')}
              </div>
            </div>
            {!user && (
              <div style={{ display: 'flex', gap: '0.5rem' }}>
                <Link href="/login" className="btn btn-outline" style={{ padding: '0.5rem 1rem', fontSize: '0.85rem' }}>
                  {t('nav_login')}
                </Link>
                <Link href="/signup" className="btn btn-primary" style={{ padding: '0.5rem 1rem', fontSize: '0.85rem' }}>
                  {t('nav_signup')}
                </Link>
              </div>
            )}
          </div>
        </section>

        {/* Reset Button */}
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '1rem' }}>
          <button
            type="button"
            onClick={resetToDefaults}
            className="btn btn-outline"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.5rem',
              color: 'var(--text-muted)',
              fontSize: '0.875rem',
            }}
          >
            <RotateCcw size={15} />
            <span>{t('reset_defaults')}</span>
          </button>
        </div>
      </div>
    </div>
  );
}
