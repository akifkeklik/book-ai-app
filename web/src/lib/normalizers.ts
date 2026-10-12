import type { Book } from '@/types';

export interface RawBookDto {
  isbn13?: string | number | null;
  isbn?: string | number | null;
  title?: string | null;
  authors?: string | null;
  author?: string | null;
  categories?: string | null;
  category?: string | null;
  description?: string | null;
  thumbnail?: string | null;
  image_url?: string | null;
  imageUrl?: string | null;

  // Rating fields
  average_rating?: number | string | null;
  averageRating?: number | string | null;
  ratings_count?: number | string | null;
  ratingsCount?: number | string | null;

  // Metadata fields
  published_date?: string | number | null;
  publishedDate?: string | number | null;
  page_count?: number | string | null;
  pageCount?: number | string | null;

  // Recommendation & AI fields
  similarity_score?: number | string | null;
  similarityScore?: number | string | null;
  recommendation_reason?: string | null;
  recommendationReason?: string | null;
  explanation?: string | null;
  explanation_source_book?: string | null;
  explanationSourceBook?: string | null;

  [key: string]: unknown;
}

function parseNumber(value: unknown, fallback: number = 0): number {
  if (typeof value === 'number' && !Number.isNaN(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (!Number.isNaN(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function parseOptionalNumber(value: unknown): number | undefined {
  if (typeof value === 'number' && !Number.isNaN(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (!Number.isNaN(parsed)) {
      return parsed;
    }
  }
  return undefined;
}

function parseOptionalString(value: unknown): string | undefined {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  }
  return undefined;
}

/**
 * Normalizes a raw book DTO (snake_case from backend or camelCase from frontend/cache)
 * into a canonical, typed Book model. Safely preserves 0 values and handles missing/null data.
 */
export function normalizeBook(raw: unknown): Book {
  if (!raw || typeof raw !== 'object') {
    return {
      isbn13: '',
      title: 'Unknown Title',
      authors: 'Unknown Author',
      categories: '',
      description: '',
      thumbnail: '',
      averageRating: 0,
      ratingsCount: 0,
      publishedDate: '',
      pageCount: 0,
    };
  }

  const r = raw as RawBookDto;

  // ISBN: support isbn13 or isbn fallback
  const rawIsbn = r.isbn13 !== undefined && r.isbn13 !== null ? r.isbn13 : r.isbn;
  const isbn13 = rawIsbn !== undefined && rawIsbn !== null ? String(rawIsbn).trim() : '';

  // Title
  const title = typeof r.title === 'string' && r.title.trim().length > 0
    ? r.title.trim()
    : 'Unknown Title';

  // Authors: support authors or author fallback
  const rawAuthors = r.authors !== undefined && r.authors !== null ? r.authors : r.author;
  const authors = typeof rawAuthors === 'string' && rawAuthors.trim().length > 0
    ? rawAuthors.trim()
    : 'Unknown Author';

  // Categories: support categories or category fallback
  const rawCategories = r.categories !== undefined && r.categories !== null ? r.categories : r.category;
  const categories = typeof rawCategories === 'string' ? rawCategories.trim() : '';

  // Description
  const description = typeof r.description === 'string' ? r.description.trim() : '';

  // Thumbnail: support thumbnail, imageUrl, or image_url
  const rawThumb = r.thumbnail !== undefined && r.thumbnail !== null
    ? r.thumbnail
    : (r.imageUrl !== undefined && r.imageUrl !== null ? r.imageUrl : r.image_url);
  const thumbnail = typeof rawThumb === 'string' ? rawThumb.trim() : '';

  // Ratings: averageRating vs average_rating, preserving numeric 0
  const rawAvg = r.averageRating !== undefined && r.averageRating !== null
    ? r.averageRating
    : r.average_rating;
  const averageRating = rawAvg !== undefined && rawAvg !== null
    ? parseNumber(rawAvg, 0)
    : 0;

  // Ratings Count: ratingsCount vs ratings_count, preserving numeric 0
  const rawCount = r.ratingsCount !== undefined && r.ratingsCount !== null
    ? r.ratingsCount
    : r.ratings_count;
  const ratingsCount = rawCount !== undefined && rawCount !== null
    ? Math.max(0, Math.floor(parseNumber(rawCount, 0)))
    : 0;

  // Published Date: publishedDate vs published_date
  const rawPubDate = r.publishedDate !== undefined && r.publishedDate !== null
    ? r.publishedDate
    : r.published_date;
  const publishedDate = rawPubDate !== undefined && rawPubDate !== null
    ? String(rawPubDate).trim()
    : '';

  // Page Count: pageCount vs page_count, preserving numeric 0
  const rawPages = r.pageCount !== undefined && r.pageCount !== null
    ? r.pageCount
    : r.page_count;
  const pageCount = rawPages !== undefined && rawPages !== null
    ? Math.max(0, Math.floor(parseNumber(rawPages, 0)))
    : 0;

  // Similarity Score: similarityScore vs similarity_score, preserving numeric 0
  const rawSim = r.similarityScore !== undefined && r.similarityScore !== null
    ? r.similarityScore
    : r.similarity_score;
  const similarityScore = rawSim !== undefined && rawSim !== null
    ? parseOptionalNumber(rawSim)
    : undefined;

  // Recommendation Reason: recommendationReason vs recommendation_reason
  const rawReason = r.recommendationReason !== undefined && r.recommendationReason !== null
    ? r.recommendationReason
    : r.recommendation_reason;
  const recommendationReason = parseOptionalString(rawReason);

  // Explanation
  const explanation = parseOptionalString(r.explanation);

  // Explanation Source Book: explanationSourceBook vs explanation_source_book
  const rawSourceBook = r.explanationSourceBook !== undefined && r.explanationSourceBook !== null
    ? r.explanationSourceBook
    : r.explanation_source_book;
  const explanationSourceBook = parseOptionalString(rawSourceBook);

  const book: Book = {
    isbn13,
    title,
    authors,
    categories,
    description,
    thumbnail,
    averageRating,
    ratingsCount,
    publishedDate,
    pageCount,
  };

  if (similarityScore !== undefined) {
    book.similarityScore = similarityScore;
  }
  if (recommendationReason !== undefined) {
    book.recommendationReason = recommendationReason;
  }
  if (explanation !== undefined) {
    book.explanation = explanation;
  }
  if (explanationSourceBook !== undefined) {
    book.explanationSourceBook = explanationSourceBook;
  }

  return book;
}

/**
 * Normalizes an array of raw book items, discarding invalid or non-object items.
 */
export function normalizeBooks(rawList: unknown): Book[] {
  if (!Array.isArray(rawList)) {
    return [];
  }

  return rawList
    .filter((item): item is Record<string, unknown> => typeof item === 'object' && item !== null)
    .map(normalizeBook);
}
