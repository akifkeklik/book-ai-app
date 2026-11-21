'use client';

import { usePreferences } from './PreferencesProvider';
import { translateGenre } from '@/lib/i18n';
import type { DiscoveryFilterType } from '@/lib/discovery';
import { Sparkles, Search, Bookmark, Heart, BookOpen } from 'lucide-react';

export interface DiscoveryFilterCounts {
  total: number;
  favorites: number;
  reading: number;
  categoryCount: number;
}

export interface DiscoveryFiltersProps {
  activeFilter: DiscoveryFilterType;
  setActiveFilter: (filter: DiscoveryFilterType) => void;
  filterCounts: DiscoveryFilterCounts;
  availableCategories: string[];
  selectedCategory: string;
  handleSelectCategory: (category: string) => void;
  searchQuery: string;
  setSearchQuery: (query: string) => void;
  /** Number of books currently shown, used for the category tab count. */
  displayedCount: number;
}

/** Recommendation filters: source tabs, category chips and a quick title/author search. */
export function DiscoveryFilters({
  activeFilter,
  setActiveFilter,
  filterCounts,
  availableCategories,
  selectedCategory,
  handleSelectCategory,
  searchQuery,
  setSearchQuery,
  displayedCount,
}: DiscoveryFiltersProps) {
  const { t, preferences } = usePreferences();

  return (
    <div
      className="glass-panel"
      style={{
        padding: '1.25rem',
        marginBottom: '2rem',
        display: 'flex',
        flexDirection: 'column',
        gap: '1.25rem',
        borderRadius: '16px',
      }}
    >
      {/* Filter Tabs: all, favorites, reading, category */}
      <div className="library-tabs" role="tablist" aria-label={t('pd_filters_label')}>
        <button
          role="tab"
          aria-selected={activeFilter === 'all'}
          onClick={() => setActiveFilter('all')}
          className={`library-tab-btn ${activeFilter === 'all' ? 'active' : ''}`}
          id="filter-all"
        >
          <Sparkles size={16} />
          <span>{t('filter_all_recommendations')}</span>
          <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({filterCounts.total})</span>
        </button>

        <button
          role="tab"
          aria-selected={activeFilter === 'favorites'}
          onClick={() => setActiveFilter('favorites')}
          className={`library-tab-btn ${activeFilter === 'favorites' ? 'active' : ''}`}
          id="filter-favorites"
        >
          <Heart size={16} color="#f472b6" fill={activeFilter === 'favorites' ? '#f472b6' : 'none'} />
          <span>{t('filter_favorites_derived')}</span>
          <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({filterCounts.favorites})</span>
        </button>

        <button
          role="tab"
          aria-selected={activeFilter === 'reading'}
          onClick={() => setActiveFilter('reading')}
          className={`library-tab-btn ${activeFilter === 'reading' ? 'active' : ''}`}
          id="filter-reading"
        >
          <Bookmark
            size={16}
            color="var(--primary)"
            fill={activeFilter === 'reading' ? 'currentColor' : 'none'}
          />
          <span>{t('filter_reading_journey')}</span>
          <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>({filterCounts.reading})</span>
        </button>

        <button
          role="tab"
          aria-selected={activeFilter === 'category'}
          onClick={() => setActiveFilter('category')}
          className={`library-tab-btn ${activeFilter === 'category' ? 'active' : ''}`}
          id="filter-category"
        >
          <BookOpen size={16} color="var(--accent-ink)" />
          <span>{t('filter_genre_category')}</span>
          <span style={{ fontSize: '0.75rem', opacity: 0.75 }}>
            ({selectedCategory !== 'all' ? displayedCount : filterCounts.categoryCount})
          </span>
        </button>
      </div>

      {/* Dynamic Category Chips row (active when 'category' tab or for quick category exploration) */}
      {activeFilter === 'category' && (
        <div
          className="animate-fade-in"
          style={{
            display: 'flex',
            gap: '0.5rem',
            alignItems: 'center',
            flexWrap: 'wrap',
            paddingTop: '0.5rem',
            borderTop: '1px solid var(--card-border)',
          }}
        >
          <span style={{ fontSize: '0.8rem', color: 'var(--muted)', fontWeight: 600 }}>
            {t('select_category_prompt')}
          </span>

          <button
            type="button"
            onClick={() => handleSelectCategory('all')}
            style={{
              fontSize: '0.78rem',
              padding: '0.3rem 0.85rem',
              borderRadius: '9999px',
              background: selectedCategory === 'all' ? 'var(--primary)' : 'var(--tint-2)',
              color: selectedCategory === 'all' ? 'var(--on-primary)' : 'var(--foreground)',
              border: '1px solid var(--card-border)',
              cursor: 'pointer',
              transition: 'all 0.2s',
            }}
          >
            {t('category_select_all')}
          </button>

          {availableCategories.map((cat) => (
            <button
              key={cat}
              type="button"
              onClick={() => handleSelectCategory(cat)}
              style={{
                fontSize: '0.78rem',
                padding: '0.3rem 0.85rem',
                borderRadius: '9999px',
                background:
                  selectedCategory.toLowerCase() === cat.toLowerCase()
                    ? 'var(--primary)'
                    : 'var(--tint-2)',
                color:
                  selectedCategory.toLowerCase() === cat.toLowerCase()
                    ? 'var(--on-primary)'
                    : 'var(--foreground)',
                border: '1px solid var(--card-border)',
                cursor: 'pointer',
                transition: 'all 0.2s',
              }}
            >
              {translateGenre(preferences.language, cat)}
            </button>
          ))}
        </div>
      )}

      {/* Quick Search in Recommendations */}
      <div style={{ position: 'relative', width: '100%', maxWidth: '450px' }}>
        <Search
          size={16}
          style={{
            position: 'absolute',
            left: '12px',
            top: '50%',
            transform: 'translateY(-50%)',
            color: 'var(--muted)',
          }}
        />
        <input
          type="text"
          placeholder={t('search')}
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="input-field"
          style={{ width: '100%', paddingLeft: '2.4rem', height: '38px', fontSize: '0.875rem' }}
          aria-label={t('pd_search_label')}
        />
      </div>
    </div>
  );
}
