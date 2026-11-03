'use client';

import { useState, useEffect } from 'react';
import { Sparkles, Check, X, Compass, Loader2 } from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import { updateUserPreferencesAction } from '@/app/actions/user';

export const AVAILABLE_GENRES = [
  'Fiction',
  'Science Fiction',
  'Fantasy',
  'Mystery',
  'History',
  'Philosophy',
  'Biography',
  'Psychology',
  'Romance',
  'Thriller',
  'Art',
  'Business',
  'Self-Help',
];

interface TasteProfileModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialGenres?: string[];
  onSaved?: (genres: string[]) => void;
}

export function TasteProfileModal({
  isOpen,
  onClose,
  initialGenres = [],
  onSaved,
}: TasteProfileModalProps) {
  const { t } = usePreferences();
  const [selectedGenres, setSelectedGenres] = useState<string[]>(initialGenres);
  const [prevInitial, setPrevInitial] = useState(initialGenres);
  if (initialGenres !== prevInitial) {
    setPrevInitial(initialGenres);
    setSelectedGenres(initialGenres);
  }
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const toggleGenre = (genre: string) => {
    setSelectedGenres((prev) =>
      prev.includes(genre) ? prev.filter((g) => g !== genre) : [...prev, genre]
    );
  };

  const handleSave = async () => {
    setIsSaving(true);
    setError(null);
    try {
      const res = await updateUserPreferencesAction(selectedGenres);
      if (res.success) {
        if (onSaved) onSaved(selectedGenres);
        onClose();
      } else {
        setError(res.error || 'Failed to save taste profile');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save preferences');
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="taste-profile-title"
      style={{
        position: 'fixed',
        inset: 0,
        backgroundColor: 'rgba(0, 0, 0, 0.75)',
        backdropFilter: 'blur(8px)',
        WebkitBackdropFilter: 'blur(8px)',
        zIndex: 9999,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '1.25rem',
      }}
    >
      <div
        className="glass-panel animate-fade-in"
        style={{
          width: '100%',
          maxWidth: '580px',
          padding: '2rem',
          borderRadius: '20px',
          background: 'var(--card)',
          border: '1px solid var(--card-border)',
          boxShadow: '0 20px 50px rgba(0, 0, 0, 0.5)',
          position: 'relative',
        }}
      >
        {/* Close / Skip button */}
        <button
          type="button"
          onClick={onClose}
          aria-label={t('cancel')}
          style={{
            position: 'absolute',
            top: '1.25rem',
            right: '1.25rem',
            background: 'var(--surface-subtle)',
            border: '1px solid var(--card-border)',
            borderRadius: '50%',
            width: '32px',
            height: '32px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'pointer',
            color: 'var(--text-muted)',
            transition: 'all 0.2s ease',
          }}
        >
          <X size={16} />
        </button>

        {/* Modal Header */}
        <div style={{ marginBottom: '1.5rem', textAlign: 'center' }}>
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.4rem',
              padding: '0.35rem 0.85rem',
              borderRadius: '9999px',
              background: 'rgba(99, 102, 241, 0.12)',
              border: '1px solid var(--card-border)',
              marginBottom: '0.75rem',
              fontSize: '0.8rem',
              fontWeight: 600,
              color: 'var(--primary)',
            }}
          >
            <Sparkles size={14} />
            <span>{t('taste_profile_title')}</span>
          </div>

          <h2 id="taste-profile-title" style={{ fontSize: '1.75rem', marginBottom: '0.5rem' }}>
            {t('onboarding_modal_title')}
          </h2>
          <p className="text-muted" style={{ fontSize: '0.9rem', maxWidth: '440px', margin: '0 auto' }}>
            {t('onboarding_modal_subtitle')}
          </p>
        </div>

        {error && (
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
              textAlign: 'center',
            }}
          >
            {error}
          </div>
        )}

        {/* Genre Chips Grid */}
        <div
          style={{
            display: 'flex',
            flexWrap: 'wrap',
            gap: '0.65rem',
            justifyContent: 'center',
            marginBottom: '2rem',
            maxHeight: '260px',
            overflowY: 'auto',
            padding: '0.25rem',
          }}
        >
          {AVAILABLE_GENRES.map((genre) => {
            const isSelected = selectedGenres.includes(genre);
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
                  padding: '0.55rem 1rem',
                  borderRadius: '9999px',
                  fontSize: '0.875rem',
                  fontWeight: isSelected ? 700 : 500,
                  cursor: 'pointer',
                  border: `1.5px solid ${isSelected ? 'var(--primary)' : 'var(--card-border)'}`,
                  background: isSelected ? 'rgba(99, 102, 241, 0.18)' : 'var(--surface-subtle)',
                  color: isSelected ? 'var(--primary)' : 'var(--text-primary)',
                  transition: 'all 0.15s ease',
                  boxShadow: isSelected ? '0 2px 8px rgba(99, 102, 241, 0.25)' : 'none',
                }}
              >
                {isSelected ? <Check size={14} /> : null}
                <span>{genre}</span>
              </button>
            );
          })}
        </div>

        {/* Selection Status indicator */}
        <div style={{ textAlign: 'center', marginBottom: '1.5rem', fontSize: '0.85rem', color: 'var(--text-muted)' }}>
          {selectedGenres.length > 0 ? (
            <span style={{ color: 'var(--primary)', fontWeight: 600 }}>
              {t('genres_selected_count', { count: selectedGenres.length })}
            </span>
          ) : (
            <span>{t('select_min_genres_hint')}</span>
          )}
        </div>

        {/* Footer CTAs */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '1rem',
            flexWrap: 'wrap',
          }}
        >
          <button
            type="button"
            onClick={onClose}
            className="btn btn-outline"
            style={{ padding: '0.75rem 1.5rem', fontSize: '0.9rem', flex: '1 1 auto' }}
          >
            {t('taste_profile_skip')}
          </button>
          <button
            type="button"
            onClick={handleSave}
            disabled={isSaving}
            className="btn btn-primary"
            style={{
              padding: '0.75rem 1.75rem',
              fontSize: '0.9rem',
              flex: '1 1 auto',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '0.5rem',
            }}
          >
            {isSaving ? <Loader2 size={16} className="animate-spin" /> : <Compass size={16} />}
            <span>{t('taste_profile_save_btn')}</span>
          </button>
        </div>
      </div>
    </div>
  );
}
