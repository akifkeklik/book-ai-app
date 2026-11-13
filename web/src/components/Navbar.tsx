'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from './AuthProvider';
import { usePreferences } from './PreferencesProvider';
import { BookOpen, LogOut, Compass, Sparkles, Bookmark, Settings, Globe, Search, Brain } from 'lucide-react';
import { LANGUAGES } from '@/lib/preferences';

export function Navbar() {
  const pathname = usePathname();
  const { user, loading, signOut } = useAuth();
  const { preferences, setLanguage, t } = usePreferences();

  const isActive = (route: string) => {
    if (route === '/') return pathname === '/';
    return pathname === route || pathname.startsWith(route + '/');
  };

  const nextLanguage = LANGUAGES[(LANGUAGES.indexOf(preferences.language) + 1) % LANGUAGES.length];

  const handleOpenSpotlight = () => {
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent('open-spotlight'));
    }
  };

  return (
    <nav className="navbar">
      <div className="container nav-container">
        <Link href="/" className="brand" aria-label={t('nav_home_label')}>
          <BookOpen size={24} color="var(--primary)" />
          <span>Libris</span>
        </Link>

        <div className="nav-links">
          {/* Spotlight Search Trigger */}
          <button
            type="button"
            onClick={handleOpenSpotlight}
            id="nav-spotlight-btn"
            className="btn btn-outline"
            style={{
              padding: '0.4rem 0.75rem',
              fontSize: '0.8rem',
              borderRadius: '9999px',
              gap: '0.4rem',
              color: 'var(--text-muted)',
            }}
            title={t('nav_search_title')}
            aria-label={t('nav_search_label')}
          >
            <Search size={14} color="var(--text-muted)" />
            <span className="nav-link-text">{t('search') || 'Search...'}</span>
            <kbd
              style={{
                fontSize: '0.65rem',
                padding: '1px 5px',
                borderRadius: '4px',
                background: 'rgba(255, 255, 255, 0.08)',
                border: '1px solid var(--card-border)',
                fontFamily: 'var(--font-mono)',
              }}
            >
              ⌘K
            </kbd>
          </button>

          <Link
            href="/catalog"
            id="nav-catalog-link"
            className={`nav-link ${isActive("/catalog") ? "active" : ""}`}
          >
            <Compass size={18} />
            <span className="nav-link-text">{t('nav_discover')}</span>
          </Link>

          <Link
            href="/ai-discovery"
            id="nav-ai-discovery-link"
            className={`nav-link ${isActive("/ai-discovery") ? "active" : ""}`}
          >
            <Sparkles size={18} color="var(--accent)" />
            <span className="text-gradient nav-link-text">{t('nav_for_you')}</span>
          </Link>

          <Link
            href="/favorites"
            id="nav-library-link"
            className={`nav-link ${isActive("/favorites") ? "active" : ""}`}
          >
            <Bookmark size={18} color="var(--primary)" />
            <span className="nav-link-text">{t('nav_my_library')}</span>
          </Link>

          <Link
            href="/learning"
            id="nav-learning-link"
            className={`nav-link ${isActive("/learning") ? "active" : ""}`}
          >
            <Brain size={18} color="var(--primary)" />
            <span className="nav-link-text">{t('nav_review')}</span>
          </Link>


          <Link
            href="/settings"
            id="nav-settings-link"
            className={`nav-link ${isActive("/settings") ? "active" : ""}`}
            title={t('nav_profile_settings')}
          >
            <Settings size={18} />
            <span className="nav-settings-label nav-link-text">{t('nav_profile_settings')}</span>
          </Link>


          {/* Quick Language Toggle */}
          <button
            type="button"
            onClick={() => setLanguage(nextLanguage)}
            className="btn btn-outline"
            style={{
              padding: '0.4rem 0.75rem',
              fontSize: '0.8rem',
              borderRadius: '9999px',
              gap: '0.35rem',
            }}
            title={t('nav_language_title')}
            aria-label={t('nav_language_title')}
          >
            <Globe size={14} color="var(--primary)" />
            <span style={{ fontWeight: 700, textTransform: 'uppercase' }}>{preferences.language}</span>
          </button>

          {!loading && (
            <>
              {user ? (
                <button
                  onClick={signOut}
                  id="nav-signout-btn"
                  className="btn btn-outline"
                  style={{ padding: '0.5rem 1rem', fontSize: '0.875rem' }}
                >
                  <LogOut size={16} />
                  <span>{t('nav_signout')}</span>
                </button>
              ) : (
                <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center' }}>
                  <Link
                    href="/login"
                    id="nav-login-btn"
                    className="btn btn-outline"
                    style={{ padding: '0.5rem 1rem', fontSize: '0.875rem' }}
                  >
                    {t('nav_login')}
                  </Link>
                  <Link
                    href="/signup"
                    id="nav-signup-btn"
                    className="btn btn-primary"
                    style={{ padding: '0.5rem 1rem', fontSize: '0.875rem' }}
                  >
                    {t('nav_signup')}
                  </Link>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
