'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Sparkles, SlidersHorizontal } from 'lucide-react';
import { TasteProfileModal } from './TasteProfileModal';
import { usePreferences } from './PreferencesProvider';

interface HomePersonalizationBannerProps {
  initialGenres?: string[];
  hasPersonalizedRecs?: boolean;
  autoOpen?: boolean;
}

export function HomePersonalizationBanner({
  initialGenres = [],
  autoOpen = false,
}: HomePersonalizationBannerProps) {
  const { t } = usePreferences();
  const router = useRouter();
  const [modalOpen, setModalOpen] = useState(autoOpen);
  const [savedGenres, setSavedGenres] = useState<string[] | null>(null);
  const genres = savedGenres ?? initialGenres;

  const handleSaved = (newGenres: string[]) => {
    setSavedGenres(newGenres);
    // Crucial: refresh server components to fetch new recommendations for the updated taste profile
    router.refresh();
  };

  return (
    <>
      <div
        className="glass-panel animate-fade-in"
        style={{
          padding: '1.75rem 2rem',
          borderRadius: '16px',
          border: '1px solid var(--card-border)',
          background: 'linear-gradient(135deg, rgba(99, 102, 241, 0.08) 0%, rgba(139, 92, 246, 0.05) 100%)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: '1.25rem',
          marginBottom: '3.5rem',
        }}
      >
        <div style={{ maxWidth: '640px' }}>
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.4rem',
              color: 'var(--primary)',
              fontWeight: 600,
              fontSize: '0.85rem',
              marginBottom: '0.4rem',
            }}
          >
            <Sparkles size={15} />
            <span>{t('taste_profile_title')}</span>
          </div>
          <h2 style={{ fontSize: '1.4rem', marginBottom: '0.4rem' }}>
            {genres.length > 0
              ? `${genres.slice(0, 3).join(', ')}${genres.length > 3 ? ` +${genres.length - 3}` : ''}`
              : t('onboarding_modal_title')}
          </h2>
          <p className="text-muted" style={{ margin: 0, fontSize: '0.9rem', lineHeight: '1.5' }}>
            {genres.length > 0
              ? t('taste_profile_subtitle')
              : t('onboarding_modal_subtitle')}
          </p>
        </div>

        <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap' }}>
          <Link
            href="/discovery/personalized"
            className="btn btn-primary"
            style={{
              padding: '0.65rem 1.25rem',
              fontSize: '0.875rem',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.5rem',
            }}
          >
            <Sparkles size={15} />
            <span>{t('personalized_discovery_cta')}</span>
          </Link>
          <button
            type="button"
            onClick={() => setModalOpen(true)}
            className="btn btn-outline"
            style={{
              padding: '0.65rem 1.25rem',
              fontSize: '0.875rem',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.5rem',
            }}
          >
            <SlidersHorizontal size={15} />
            <span>{genres.length > 0 ? t('taste_profile_title') : t('onboarding_modal_title')}</span>
          </button>
        </div>
      </div>

      <TasteProfileModal
        isOpen={modalOpen}
        onClose={() => setModalOpen(false)}
        initialGenres={genres}
        onSaved={handleSaved}
      />
    </>
  );
}
