import type {
  Book,
  ReviewItem,
  ReviewAttempt,
  LearningProgress,
} from '@/types';

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
  explanation_type?: string | null;
  explanationType?: string | null;
  confidence?: 'high' | 'medium' | 'cold_start' | null;
  is_cold_start?: boolean | null;
  isColdStart?: boolean | null;

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

  const rawType = r.explanationType !== undefined && r.explanationType !== null
    ? r.explanationType
    : r.explanation_type;
  const explanationType = parseOptionalString(rawType);
  if (explanationType !== undefined) {
    book.explanationType = explanationType;
  }

  const rawConfidence = parseOptionalString(r.confidence);
  if (rawConfidence === 'high' || rawConfidence === 'medium' || rawConfidence === 'cold_start') {
    book.confidence = rawConfidence;
  }

  const isColdStart = Boolean(r.isColdStart || r.is_cold_start);
  if (isColdStart || r.isColdStart !== undefined || r.is_cold_start !== undefined) {
    book.isColdStart = isColdStart;
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

export function normalizeReviewItem(raw: Record<string, unknown> | null | undefined): ReviewItem {
  return {
    id: String(raw?.id || ''),
    userId: String(raw?.user_id || raw?.userId || ''),
    title: String(raw?.title || ''),
    concept: String(raw?.concept || ''),
    question: String(raw?.question || ''),
    answer: String(raw?.answer || ''),
    explanation: String(raw?.explanation || ''),
    sourceType: String(raw?.source_type || raw?.sourceType || 'user_created'),
    sourceId: raw?.source_id !== undefined ? (raw.source_id ? String(raw.source_id) : null) : (raw?.sourceId ? String(raw.sourceId) : null),
    bookId: raw?.book_id !== undefined ? (raw.book_id ? String(raw.book_id) : null) : (raw?.bookId ? String(raw.bookId) : null),
    stage: Number(raw?.stage || 1),
    intervalDays: Number(raw?.interval_days || raw?.intervalDays || 1),
    nextReviewAt: raw?.next_review_at ? String(raw.next_review_at) : (raw?.nextReviewAt ? String(raw.nextReviewAt) : undefined),
    lastReviewedAt: raw?.last_reviewed_at ? String(raw.last_reviewed_at) : (raw?.lastReviewedAt ? String(raw.lastReviewedAt) : null),
    totalReviews: Number(raw?.total_reviews || raw?.totalReviews || 0),
    successfulReviews: Number(raw?.successful_reviews || raw?.successfulReviews || 0),
    status: String(raw?.status || 'active'),
    metadata: typeof raw?.metadata === 'object' && raw?.metadata !== null ? (raw.metadata as Record<string, unknown>) : {},
    createdAt: raw?.created_at ? String(raw.created_at) : (raw?.createdAt ? String(raw.createdAt) : undefined),
    updatedAt: raw?.updated_at ? String(raw.updated_at) : (raw?.updatedAt ? String(raw.updatedAt) : undefined),
    book: raw?.book ? normalizeBook(raw.book as Record<string, unknown>) : null,
    priority: typeof raw?.priority === 'number' ? raw.priority : undefined,
    recommendationReason: raw?.recommendation_reason ? String(raw.recommendation_reason) : (raw?.recommendationReason ? String(raw.recommendationReason) : undefined),
    recommendationReasonKey: raw?.recommendation_reason_key ? String(raw.recommendation_reason_key) : (raw?.recommendationReasonKey ? String(raw.recommendationReasonKey) : undefined),
  };
}

export function normalizeReviewAttempt(raw: Record<string, unknown> | null | undefined): ReviewAttempt {
  return {
    id: raw?.id ? String(raw.id) : undefined,
    userId: String(raw?.user_id || raw?.userId || ''),
    itemId: String(raw?.item_id || raw?.itemId || ''),
    outcome: (raw?.outcome || 'struggled') as 'remembered' | 'struggled',
    responseText: String(raw?.response_text || raw?.responseText || ''),
    isCorrect: Boolean(raw?.is_correct !== undefined ? raw.is_correct : raw?.isCorrect),
    stageBefore: Number(raw?.stage_before || raw?.stageBefore || 1),
    stageAfter: Number(raw?.stage_after || raw?.stageAfter || 1),
    reviewedAt: raw?.reviewed_at ? String(raw.reviewed_at) : (raw?.reviewedAt ? String(raw.reviewedAt) : undefined),
    createdAt: raw?.created_at ? String(raw.created_at) : (raw?.createdAt ? String(raw.createdAt) : undefined),
    itemTitle: raw?.item_title ? String(raw.item_title) : (raw?.itemTitle ? String(raw.itemTitle) : undefined),
    concept: raw?.concept ? String(raw.concept) : undefined,
    bookId: raw?.book_id ? String(raw.book_id) : (raw?.bookId ? String(raw.bookId) : undefined),
  };
}

export function normalizeLearningProgress(raw: Record<string, unknown> | null | undefined): LearningProgress {
  const rawDifficult = (raw?.difficult_concepts || raw?.difficultConcepts) as unknown;
  const diffConcepts = Array.isArray(rawDifficult)
    ? (rawDifficult as Record<string, unknown>[]).map((c: Record<string, unknown>) => ({
        concept: String(c?.concept || ''),
        totalItems: Number(c?.total_items || c?.totalItems || 0),
        totalAttempts: Number(c?.total_attempts || c?.totalAttempts || 0),
        successfulRecalls: Number(c?.successful_recalls || c?.successfulRecalls || 0),
        struggledRecalls: Number(c?.struggled_recalls || c?.struggledRecalls || 0),
        retentionRate: Number(c?.retention_rate !== undefined ? c.retention_rate : c?.retentionRate || 0),
        averageStage: Number(c?.average_stage || c?.averageStage || 1),
        dueItems: Number(c?.due_items || c?.dueItems || 0),
        needsReview: Boolean(c?.needs_review !== undefined ? c.needs_review : c?.needsReview),
      }))
    : [];

  const rawActivity = (raw?.recent_activity || raw?.recentActivity) as unknown;
  const activity = Array.isArray(rawActivity)
    ? (rawActivity as (Record<string, unknown> | null | undefined)[]).map(normalizeReviewAttempt)
    : [];

  return {
    masteryScore: Number(raw?.mastery_score !== undefined ? raw.mastery_score : raw?.masteryScore || 0),
    masteryLevel: String(raw?.mastery_level || raw?.masteryLevel || 'insufficient_data'),
    totalItems: Number(raw?.total_items || raw?.totalItems || 0),
    reviewsDue: Number(raw?.reviews_due || raw?.reviewsDue || 0),
    reviewsCompleted: Number(raw?.reviews_completed || raw?.reviewsCompleted || 0),
    successfulRecalls: Number(raw?.successful_recalls || raw?.successfulRecalls || 0),
    struggledRecalls: Number(raw?.struggled_recalls || raw?.struggledRecalls || 0),
    retentionRate: Number(raw?.retention_rate !== undefined ? raw.retention_rate : raw?.retentionRate || 0),
    conceptsCount: Number(raw?.concepts_count || raw?.conceptsCount || 0),
    difficultConcepts: diffConcepts,
    recentActivity: activity,
    activeStreakDays: Number(raw?.active_streak_days || raw?.activeStreakDays || 0),
    algorithmVersion: String(raw?.algorithm_version || raw?.algorithmVersion || 'v1'),
  };
}
