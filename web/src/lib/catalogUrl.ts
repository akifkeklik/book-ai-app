export interface CatalogFilterState {
  category?: string;
  query?: string;
  sort?: string;
  order?: 'asc' | 'desc';
  min_rating?: number;
}

export type CatalogUrlOverrides = Record<string, string | number | undefined | null>;

/**
 * Builds a /catalog URL from the current filters plus overrides.
 * Pure and serializable-input only, so both server and client components can call it
 * (functions cannot be passed from server to client components as props).
 */
export function buildCatalogUrl(filters: CatalogFilterState, overrides: CatalogUrlOverrides): string {
  const params = new URLSearchParams();
  if (filters.category) params.set('category', filters.category);
  if (filters.query) params.set('q', filters.query);
  if (filters.sort && filters.sort !== 'popularity') params.set('sort', filters.sort);
  if (filters.order && filters.order !== 'desc') params.set('order', filters.order);
  if (filters.min_rating) params.set('min_rating', String(filters.min_rating));

  // Reset page to 1 when changing filters, unless explicitly passing page
  if (!('page' in overrides)) {
    params.delete('page');
  }

  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined || value === null || value === '') {
      params.delete(key);
    } else {
      params.set(key, String(value));
    }
  }

  const queryStr = params.toString();
  return queryStr ? `/catalog?${queryStr}` : '/catalog';
}
