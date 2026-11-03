import type { Book } from '@/types';

export type DiscoveryFilterType = 'all' | 'favorites' | 'reading' | 'category';

export type ClassifiedSource = 'favorites' | 'reading' | 'category' | 'general';

/**
 * Classifies a recommended book based on transparent recommendation attribution.
 * Follows exact semantics shared with Libris mobile client and backend ML recommender.
 */
export function classifyRecommendation(book: Book): ClassifiedSource {
  const reason = (book.recommendationReason || book.explanation || '').toLowerCase();

  if (
    reason.includes('favorite') ||
    reason.includes('favorited') ||
    reason.includes('favori')
  ) {
    return 'favorites';
  }

  if (
    reason.includes('read') ||
    reason.includes('reading') ||
    reason.includes('okuma') ||
    reason.includes('okudu') ||
    reason.includes('gelesen')
  ) {
    return 'reading';
  }

  if (
    reason.includes('enjoy') ||
    reason.includes('genre') ||
    reason.includes('taste') ||
    reason.includes('author') ||
    reason.includes('tür') ||
    reason.includes('yazar') ||
    reason.includes('zevk') ||
    reason.includes('geschmack')
  ) {
    return 'category';
  }

  return 'general';
}

/**
 * Filters a list of recommended books based on the selected discovery filter.
 * Ensures genuine, non-fabricated discovery by returning empty lists when
 * no attribution matches, instead of inventing fake sources.
 */
export function filterRecommendations(
  books: Book[],
  filter: DiscoveryFilterType,
  selectedCategory?: string
): Book[] {
  if (!Array.isArray(books)) return [];

  if (filter === 'all') {
    return books;
  }

  if (filter === 'favorites') {
    return books.filter((b) => classifyRecommendation(b) === 'favorites');
  }

  if (filter === 'reading') {
    return books.filter((b) => classifyRecommendation(b) === 'reading');
  }

  if (filter === 'category') {
    if (selectedCategory && selectedCategory.trim() && selectedCategory.toLowerCase() !== 'all') {
      const cleanCat = selectedCategory.trim().toLowerCase();
      return books.filter((b) => {
        const catStr = (b.categories || '').toLowerCase();
        return catStr.includes(cleanCat);
      });
    }
    return books.filter(
      (b) => classifyRecommendation(b) === 'category' || Boolean((b.categories || '').trim())
    );
  }

  return books;
}

