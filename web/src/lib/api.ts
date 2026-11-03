import { createClient } from './supabase/server';
import type {
  Book,
  Category,
  PaginatedResponse,
  AiChatResponse,
  LibraryCollectionStatus,
  LibraryItem,
  LearningNote,
  NoteType,
  NoteReview,
  NoteReviewStats,
  ExportNotesResult,
  LearningPath,
  LearningPathItem,
  CreateLearningPathInput,
  UserTasteProfile,
  KnowledgeEdge,
  KnowledgeGraphData,
  CreateRelationshipInput,
  ReviewItem,
  ReviewAttempt,
  LearningProgress,
  DifficultConcept,
  CreateReviewItemInput,
  SubmitReviewAttemptInput,
} from '@/types';
import { normalizeBook, normalizeBooks, normalizeKnowledgeGraph, normalizeKnowledgeEdge, normalizeReviewItem, normalizeReviewAttempt, normalizeLearningProgress } from './normalizers';

const API_URL = process.env.BACKEND_URL || 'http://localhost:5000';
export const DEFAULT_API_TIMEOUT_MS = 10000;

export class ApiTimeoutError extends Error {
  readonly isTimeout = true;
  readonly code = 'ETIMEDOUT';
  constructor(message: string) {
    super(message);
    this.name = 'ApiTimeoutError';
  }
}

/**
 * Validates and normalizes ISBN inputs.
 * Strips formatting hyphens and spaces.
 * Supports standard ISBN-13 (13 digits) and ISBN-10 (9 digits + 1 digit/X).
 * Rejects path traversal, query/hash delimiters, control chars, and malformed strings.
 */
export function normalizeIsbn(isbn: string): string | null {
  if (!isbn || typeof isbn !== 'string') return null;

  // Reject path traversal, delimiters, control characters, quotes, brackets
  if (/[/\\?#%<>\x00-\x1f"'{}`]/.test(isbn)) {
    return null;
  }

  // Strip hyphens and whitespace
  const cleaned = isbn.replace(/[-\s]/g, '').trim();
  if (!cleaned) return null;

  // 13-digit standard ISBN
  if (/^\d{13}$/.test(cleaned)) {
    return cleaned;
  }

  // 10-digit standard ISBN: convert to canonical 13-digit ISBN
  if (/^\d{9}[\dX]$/i.test(cleaned)) {
    const core = '978' + cleaned.substring(0, 9);
    let sum = 0;
    for (let i = 0; i < 12; i++) {
      sum += parseInt(core[i], 10) * (i % 2 === 0 ? 1 : 3);
    }
    const check = (10 - (sum % 10)) % 10;
    return core + check;
  }

  return null;
}

export function isValidIsbn(isbn: string): boolean {
  return normalizeIsbn(isbn) !== null;
}


function normalizeLearningNote(raw: Record<string, unknown>): LearningNote {
  const rawBook = (raw?.book && typeof raw.book === 'object') ? (raw.book as Record<string, unknown>) : undefined;
  return {
    id: String(raw?.id || ''),
    userId: String(raw?.user_id || raw?.userId || ''),
    bookId: String(raw?.book_id || raw?.bookId || ''),
    noteType: ((raw?.note_type || raw?.noteType || 'personal_note') as NoteType),
    content: String(raw?.content || ''),
    createdAt: String(raw?.created_at || raw?.createdAt || new Date().toISOString()),
    updatedAt: String(raw?.updated_at || raw?.updatedAt || new Date().toISOString()),
    clientId: raw?.client_id ? String(raw.client_id) : (raw?.clientId ? String(raw.clientId) : undefined),
    reviewStage: typeof raw?.stage === 'number' ? raw.stage : (typeof raw?.reviewStage === 'number' ? raw.reviewStage : undefined),
    nextReviewAt: raw?.next_review_at ? String(raw.next_review_at) : (raw?.nextReviewAt ? String(raw.nextReviewAt) : undefined),
    isReviewDue: Boolean(raw?.is_review_due || raw?.isReviewDue),
    book: rawBook ? {
      isbn13: String(rawBook.isbn13 || ''),
      title: String(rawBook.title || ''),
      authors: String(rawBook.authors || ''),
      thumbnail: String(rawBook.thumbnail || ''),
    } : undefined,
  };
}


function normalizeLearningPathItem(raw: Record<string, unknown>): LearningPathItem {
  const rawBook = (raw?.book && typeof raw.book === 'object') ? (raw.book as Record<string, unknown>) : undefined;
  return {
    bookId: String(raw?.book_id || raw?.bookId || ''),
    orderIndex: typeof raw?.order_index === 'number' ? raw.order_index : (typeof raw?.orderIndex === 'number' ? raw.orderIndex : 0),
    addedAt: raw?.added_at ? String(raw.added_at) : undefined,
    book: rawBook ? normalizeBook(rawBook) : undefined,
    readingStatus: (raw?.reading_status || raw?.readingStatus || null) as ('want_to_read' | 'reading' | 'finished' | null),
    notesCount: typeof raw?.notes_count === 'number' ? raw.notes_count : (typeof raw?.notesCount === 'number' ? raw.notesCount : 0),
    hasDueReview: Boolean(raw?.has_due_review || raw?.hasDueReview),
  };
}

function normalizeLearningPath(raw: Record<string, unknown>): LearningPath {
  const rawBooks = Array.isArray(raw?.books) ? raw.books : [];
  return {
    id: String(raw?.id || ''),
    userId: String(raw?.user_id || raw?.userId || ''),
    title: String(raw?.title || ''),
    description: String(raw?.description || ''),
    category: String(raw?.category || ''),
    status: (raw?.status as 'active' | 'completed' | 'archived') || 'active',
    books: rawBooks.map((b: Record<string, unknown>) => normalizeLearningPathItem(b)),
    createdAt: String(raw?.created_at || raw?.createdAt || new Date().toISOString()),
    updatedAt: String(raw?.updated_at || raw?.updatedAt || new Date().toISOString()),
    totalBooks: typeof raw?.total_books === 'number' ? raw.total_books : (typeof raw?.totalBooks === 'number' ? raw.totalBooks : rawBooks.length),
    completedBooks: typeof raw?.completed_books === 'number' ? raw.completed_books : (typeof raw?.completedBooks === 'number' ? raw.completedBooks : 0),
    readingBooks: typeof raw?.reading_books === 'number' ? raw.reading_books : (typeof raw?.readingBooks === 'number' ? raw.readingBooks : 0),
    notStartedBooks: typeof raw?.not_started_books === 'number' ? raw.not_started_books : (typeof raw?.notStartedBooks === 'number' ? raw.notStartedBooks : 0),
    progressPercent: typeof raw?.progress_percent === 'number' ? raw.progress_percent : (typeof raw?.progressPercent === 'number' ? raw.progressPercent : 0),
    totalNotesCount: typeof raw?.total_notes_count === 'number' ? raw.total_notes_count : (typeof raw?.totalNotesCount === 'number' ? raw.totalNotesCount : 0),
    totalReviewsDue: typeof raw?.total_reviews_due === 'number' ? raw.total_reviews_due : (typeof raw?.totalReviewsDue === 'number' ? raw.totalReviewsDue : 0),
    nextBookId: raw?.next_book_id ? String(raw.next_book_id) : (raw?.nextBookId ? String(raw.nextBookId) : null),
  };
}
function normalizeNoteReview(raw: Record<string, unknown>): NoteReview {
  const rawNote = (raw?.note && typeof raw.note === 'object') ? (raw.note as Record<string, unknown>) : undefined;
  return {
    id: String(raw?.id || ''),
    noteId: String(raw?.note_id || raw?.noteId || ''),
    userId: String(raw?.user_id || raw?.userId || ''),
    stage: typeof raw?.stage === 'number' ? raw.stage : 1,
    intervalDays: typeof raw?.interval_days === 'number' ? raw.interval_days : (typeof raw?.intervalDays === 'number' ? raw.intervalDays : 1),
    nextReviewAt: String(raw?.next_review_at || raw?.nextReviewAt || new Date().toISOString()),
    lastReviewedAt: raw?.last_reviewed_at ? String(raw.last_reviewed_at) : (raw?.lastReviewedAt ? String(raw.lastReviewedAt) : null),
    reviewCount: typeof raw?.review_count === 'number' ? raw.review_count : (typeof raw?.reviewCount === 'number' ? raw.reviewCount : 0),
    status: (raw?.status as 'active' | 'completed' | 'paused') || 'active',
    note: rawNote ? normalizeLearningNote(rawNote) : undefined,
  };
}

export class ApiService {
  private static async fetchWithTimeout(
    url: string,
    options: RequestInit = {},
    timeoutMs: number = DEFAULT_API_TIMEOUT_MS
  ): Promise<Response> {
    const controller = new AbortController();
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, timeoutMs);

    if (options.signal) {
      if (options.signal.aborted) {
        clearTimeout(timer);
        controller.abort(options.signal.reason);
      } else {
        options.signal.addEventListener('abort', () => {
          clearTimeout(timer);
          controller.abort(options.signal?.reason);
        });
      }
    }

    try {
      const res = await fetch(url, {
        ...options,
        signal: controller.signal,
      });
      return res;
    } catch (err: unknown) {
      if (timedOut || (err instanceof Error && err.name === 'TimeoutError')) {
        throw new ApiTimeoutError(`Request to ${url} timed out after ${timeoutMs}ms`);
      }
      throw err;
    } finally {
      clearTimeout(timer);
    }
  }

  static async getHeaders(isPublic: boolean = false): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    const rawApiKey = process.env.LIBRIS_API_KEY;
    if (typeof rawApiKey === 'string' && rawApiKey.trim().length > 0) {
      headers['X-Api-Key'] = rawApiKey.trim();
    }

    if (isPublic) {
      // Public requests do not attach user sessions or cookies.
      // This guarantees no authenticated tokens leak into shared caches,
      // and prevents Next.js from opting out of static prerendering.
      return headers;
    }

    try {
      const supabase = await createClient();
      let hasValidUser = false;
      if (typeof supabase.auth.getUser === 'function') {
        const { data: { user }, error } = await supabase.auth.getUser();
        hasValidUser = !!user && !error;
        if (hasValidUser && user?.id) {
          headers['X-User-Id'] = user.id;
        }
      } else {
        hasValidUser = true;
      }

      if (hasValidUser) {
        const { data: { session } } = await supabase.auth.getSession();
        if (session?.access_token) {
          headers['Authorization'] = `Bearer ${session.access_token}`;
        }
      }
    } catch {
      // Ignore: session is optional and request store may be absent in testing/static generation
    }

    return headers;
  }

  // Public catalog taxonomy: static / infrequently changed, cached with tag 'categories'
  static async getCategories(options: { signal?: AbortSignal } = {}): Promise<Category[]> {
    const headers = await this.getHeaders(true);
    const res = await this.fetchWithTimeout(`${API_URL}/api/categories`, {
      headers,
      signal: options.signal,
      next: { revalidate: 3600, tags: ['categories'] },
    } as RequestInit);
    if (!res.ok) throw new Error('Failed to fetch categories');
    
    const data = await res.json();
    return data.categories || [];
  }

  // Public catalog search and pagination: cached with tag 'catalog'
  static async getBooks(
    params: {
      page?: number;
      per_page?: number;
      category?: string;
      query?: string;
      sort?: string;
      order?: string;
      min_rating?: number;
      min_pages?: number;
      max_pages?: number;
      signal?: AbortSignal;
    } = {}
  ): Promise<PaginatedResponse<Book>> {
    const headers = await this.getHeaders(true);
    const url = new URL(`${API_URL}/api/books`);
    
    if (params.page) url.searchParams.append('page', params.page.toString());
    if (params.per_page) url.searchParams.append('per_page', params.per_page.toString());
    if (params.category && params.category !== 'all') url.searchParams.append('category', params.category);
    if (params.query) url.searchParams.append('q', params.query);
    if (params.sort) url.searchParams.append('sort', params.sort);
    if (params.order) url.searchParams.append('order', params.order);
    if (params.min_rating) url.searchParams.append('min_rating', params.min_rating.toString());
    if (params.min_pages) url.searchParams.append('min_pages', params.min_pages.toString());
    if (params.max_pages) url.searchParams.append('max_pages', params.max_pages.toString());

    const categoryTag = params.category && params.category !== 'all'
      ? `catalog-${encodeURIComponent(params.category.toLowerCase())}`
      : 'catalog-all';

    const res = await this.fetchWithTimeout(url.toString(), {
      headers,
      signal: params.signal,
      next: { revalidate: 300, tags: ['catalog', categoryTag] },
    } as RequestInit);
    if (!res.ok) throw new Error('Failed to fetch books');
    
    const data = await res.json();
    return {
      books: normalizeBooks(data?.books),
      total: typeof data?.total === 'number' ? data.total : (Array.isArray(data?.books) ? data.books.length : 0),
      total_pages: typeof data?.total_pages === 'number' ? data.total_pages : 1,
    };
  }

  // Public book details: cached with tag 'books' and 'book-<isbn>'
  static async getBookByIsbn(
    isbn: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<Book | null> {
    const normalized = normalizeIsbn(isbn);
    if (!normalized) {
      return null;
    }

    const headers = await this.getHeaders(true);
    const encoded = encodeURIComponent(normalized);
    const res = await this.fetchWithTimeout(`${API_URL}/api/books/${encoded}`, {
      headers,
      signal: options.signal,
      next: { revalidate: 3600, tags: ['books', `book-${normalized}`] },
    } as RequestInit);
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`Failed to fetch book details (${res.status})`);
    
    const data = await res.json();
    return data?.book ? normalizeBook(data.book) : null;
  }

  // Public title-based recommendations: cached with tag 'recommendations'
  static async getRecommendations(
    bookTitle: string,
    topN: number = 20,
    options: { signal?: AbortSignal } = {}
  ): Promise<Book[]> {
    const headers = await this.getHeaders(true);
    const url = new URL(`${API_URL}/api/recommend`);
    url.searchParams.append('book', bookTitle);
    url.searchParams.append('top_n', topN.toString());
    url.searchParams.append('hybrid', 'true');
    
    const res = await this.fetchWithTimeout(url.toString(), {
      headers,
      signal: options.signal,
      next: { revalidate: 300, tags: ['recommendations'] },
    } as RequestInit);
    if (!res.ok) throw new Error('Failed to fetch recommendations');
    
    const data = await res.json();
    return normalizeBooks(data?.recommendations);
  }

  // Interactive AI query: dynamic generative inference, cache: 'no-store'
  static async chatWithAI(
    query: string,
    options: { signal?: AbortSignal; timeoutMs?: number } = {}
  ): Promise<AiChatResponse> {
    const headers = await this.getHeaders();
    const timeoutMs = options.timeoutMs ?? 30000;
    const res = await this.fetchWithTimeout(
      `${API_URL}/api/ai/chat`,
      {
        method: 'POST',
        headers,
        body: JSON.stringify({ query }),
        cache: 'no-store',
        signal: options.signal,
      },
      timeoutMs
    );
    
    if (!res.ok) {
      let errorMessage = `Failed to chat with AI (${res.status})`;
      try {
        const errData = await res.json();
        if (errData && typeof errData === 'object' && errData.error) {
          errorMessage = String(errData.error);
        }
      } catch {
        // Fall back to default message if response body is non-JSON
      }
      throw new Error(errorMessage);
    }
    
    const data = await res.json();
    const rawList = Array.isArray(data?.referenced_books)
      ? data.referenced_books
      : (Array.isArray(data?.referencedBooks)
        ? data.referencedBooks
        : (Array.isArray(data?.recommendations) ? data.recommendations : []));

    const normalizedBooks = normalizeBooks(rawList);
    const action = data?.action && typeof data.action === 'object' && typeof data.action.type === 'string'
      ? { type: data.action.type, payload: (data.action.payload || {}) }
      : null;

    return {
      answer: typeof data?.answer === 'string' ? data.answer : '',
      referencedBooks: normalizedBooks,
      recommendations: normalizedBooks,
      status: typeof data?.status === 'string' ? data.status : 'success',
      action,
    };
  }

  // User-specific personalized recommendations: requires cache: 'no-store'
  static async getPersonalizedRecommendations(
    limit: number = 10,
    options: { category?: string; excludeCompleted?: boolean; pathId?: string; signal?: AbortSignal } = {}
  ): Promise<Book[]> {
    const res = await this.getPersonalizedRecommendationsWithMeta(limit, options);
    return res.books;
  }

  static async getPersonalizedRecommendationsWithMeta(
    limit: number = 10,
    options: { category?: string; excludeCompleted?: boolean; pathId?: string; signal?: AbortSignal } = {}
  ): Promise<{
    books: Book[];
    isColdStart: boolean;
    evidenceCoverage: 'cold_start' | 'emerging' | 'established';
    total: number;
  }> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/recommend/personalized`);
    url.searchParams.append('limit', limit.toString());
    if (options.category && options.category.trim() && options.category.toLowerCase() !== 'all') {
      url.searchParams.append('category', options.category.trim());
    }
    if (options.excludeCompleted !== undefined) {
      url.searchParams.append('exclude_completed', options.excludeCompleted ? 'true' : 'false');
    }
    if (options.pathId && options.pathId.trim()) {
      url.searchParams.append('path_id', options.pathId.trim());
    }
    
    const res = await this.fetchWithTimeout(url.toString(), {
      headers,
      cache: 'no-store',
      signal: options.signal,
    });
    if (res.status === 401) {
      throw new Error('Unauthorized');
    }
    if (!res.ok) throw new Error('Failed to fetch personalized recommendations');
    
    const data = await res.json();
    return {
      books: normalizeBooks(data?.recommendations),
      isColdStart: Boolean(data?.is_cold_start),
      evidenceCoverage: (data?.evidence_coverage as 'cold_start' | 'emerging' | 'established') || 'cold_start',
      total: typeof data?.total === 'number' ? data.total : (Array.isArray(data?.recommendations) ? data.recommendations.length : 0),
    };
  }

  static async getLearningPathRecommendations(
    pathId: string,
    limit: number = 10,
    options: { excludeCompleted?: boolean; signal?: AbortSignal } = {}
  ): Promise<Book[]> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/learning-paths/${encodeURIComponent(pathId)}/recommendations`);
    url.searchParams.append('limit', limit.toString());
    if (options.excludeCompleted !== undefined) {
      url.searchParams.append('exclude_completed', options.excludeCompleted ? 'true' : 'false');
    }
    const res = await this.fetchWithTimeout(url.toString(), {
      headers,
      cache: 'no-store',
      signal: options.signal,
    });
    if (!res.ok) return [];
    const data = await res.json();
    return normalizeBooks(data?.suggestions);
  }

  static async getUserTasteProfile(
    options: { signal?: AbortSignal } = {}
  ): Promise<UserTasteProfile | null> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/taste-profile`, {
      headers,
      cache: 'no-store',
      signal: options.signal,
    });
    if (!res.ok) return null;
    return await res.json();
  }

  static async resetPersonalization(
    options: { signal?: AbortSignal } = {}
  ): Promise<boolean> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/preferences/reset`, {
      method: 'POST',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });
    return res.ok;
  }

  // Feedback mutation: cache: 'no-store'
  static async submitFeedback(
    bookId: string,
    interaction: 'like' | 'dislike' | 'favorite' | 'unfavorite' | 'want_to_read' | 'reading' | 'finished' | 'clear' | 'remove',
    options: { signal?: AbortSignal } = {}
  ): Promise<boolean> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/feedback`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ book_id: bookId, interaction }),
      cache: 'no-store',
      signal: options.signal,
    });
    return res.ok;
  }

  // Activity tracking mutation: cache: 'no-store'
  static async trackActivity(
    bookId: string,
    action: string = 'view',
    options: { signal?: AbortSignal } = {}
  ): Promise<boolean> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/track`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ book_id: bookId, action }),
      cache: 'no-store',
      signal: options.signal,
    });
    return res.ok;
  }

  // Taste Profile Preferences: cache: 'no-store'
  static async getUserPreferences(
    options: { signal?: AbortSignal } = {}
  ): Promise<{ preferredGenres: string[]; preferredAuthors: string[] }> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/preferences`, {
      headers,
      cache: 'no-store',
      signal: options.signal,
    });
    if (!res.ok) {
      return { preferredGenres: [], preferredAuthors: [] };
    }
    const data = await res.json();
    return {
      preferredGenres: Array.isArray(data?.preferred_genres) ? data.preferred_genres : [],
      preferredAuthors: Array.isArray(data?.preferred_authors) ? data.preferred_authors : [],
    };
  }

  // Update Taste Profile Preferences: cache: 'no-store'
  static async updateUserPreferences(
    genres: string[],
    authors?: string[],
    options: { signal?: AbortSignal } = {}
  ): Promise<boolean> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/preferences`, {
      method: 'PUT',
      headers,
      body: JSON.stringify({ genres, authors }),
      cache: 'no-store',
      signal: options.signal,
    });
    return res.ok;
  }

  // Library collection for authenticated user: cache: 'no-store'
  static async getLibraryBooks(
    options: { signal?: AbortSignal } = {}
  ): Promise<LibraryItem[]> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/library`, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) {
        throw new Error('Unauthorized: Please sign in to view your library');
      }
      throw new Error(`Failed to fetch library (${res.status})`);
    }

    const data = await res.json();
    const rawItems = Array.isArray(data?.items) ? data.items : [];

    return rawItems.map((item: Record<string, unknown>) => ({
      id: String(item.id || item.book_id),
      bookId: String(item.book_id || item.id),
      status: (item.status as LibraryCollectionStatus) || 'favorite',
      isFavorite: Boolean(item.is_favorite ?? (item.status === 'favorite')),
      addedAt: (item.added_at as string) || new Date().toISOString(),
      book: normalizeBook(
        (item.book as Record<string, unknown>) || { isbn13: item.book_id }
      ),
    }));
  }

  // Book interaction status for authenticated user: cache: 'no-store'
  static async getBookInteraction(
    bookId: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<{
    interaction: LibraryCollectionStatus | 'like' | 'dislike' | null;
    isFavorite: boolean;
    isAuthenticated: boolean;
  }> {
    if (!bookId || typeof bookId !== 'string') {
      return { interaction: null, isFavorite: false, isAuthenticated: false };
    }

    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(bookId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/feedback/${encoded}`, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) {
        return { interaction: null, isFavorite: false, isAuthenticated: false };
      }
      throw new Error(`Failed to retrieve book interaction (${res.status})`);
    }

    const data = await res.json();
    return {
      interaction: (data?.interaction as LibraryCollectionStatus | 'like' | 'dislike') || null,
      isFavorite: Boolean(data?.is_favorite),
      isAuthenticated: Boolean(data?.is_authenticated),
    };
  }

  // ── Learning Notes & Knowledge Retention ─────────────────────────────────────

  static async getNotes(
    params: {
      bookId?: string;
      noteType?: NoteType;
      query?: string;
      limit?: number;
      offset?: number;
    } = {},
    options: { signal?: AbortSignal } = {}
  ): Promise<{ notes: LearningNote[]; total: number }> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/notes`);
    if (params.bookId) url.searchParams.append('book_id', params.bookId.trim());
    if (params.noteType) url.searchParams.append('note_type', params.noteType);
    if (params.query) url.searchParams.append('q', params.query.trim());
    if (params.limit) url.searchParams.append('limit', params.limit.toString());
    if (params.offset) url.searchParams.append('offset', params.offset.toString());

    const res = await this.fetchWithTimeout(url.toString(), {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) {
        throw new Error('Unauthorized');
      }
      throw new Error(`Failed to fetch learning notes (${res.status})`);
    }

    const data = await res.json();
    const rawList = Array.isArray(data?.notes) ? data.notes : [];
    return {
      notes: rawList.map((item: Record<string, unknown>) => normalizeLearningNote(item)),
      total: typeof data?.total === 'number' ? data.total : rawList.length,
    };
  }

  static async getBookNotes(
    bookId: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningNote[]> {
    if (!bookId) return [];
    const result = await this.getNotes({ bookId }, options);
    return result.notes;
  }

  static async createNote(
    bookId: string,
    noteType: NoteType,
    content: string,
    clientId?: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningNote> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/notes`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        book_id: bookId,
        note_type: noteType,
        content,
        ...(clientId ? { client_id: clientId } : {}),
      }),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData?.error || `Failed to create note (${res.status})`);
    }

    const data = await res.json();
    return normalizeLearningNote(data?.note || {});
  }

  static async updateNote(
    noteId: string,
    content: string,
    noteType?: NoteType,
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningNote> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(noteId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/notes/${encoded}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify({ content, ...(noteType ? { note_type: noteType } : {}) }),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData?.error || `Failed to update note (${res.status})`);
    }

    const data = await res.json();
    return normalizeLearningNote(data?.note || {});
  }

  static async deleteNote(
    noteId: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<boolean> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(noteId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/notes/${encoded}`, {
      method: 'DELETE',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });
    return res.ok;
  }

  // ── Smart Review & Spaced Repetition ────────────────────────────────────────

  static async getDueReviews(
    limit: number = 50,
    options: { signal?: AbortSignal } = {}
  ): Promise<NoteReview[]> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/notes/reviews/due?limit=${limit}`, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) throw new Error('Unauthorized');
      throw new Error(`Failed to fetch due reviews (${res.status})`);
    }

    const data = await res.json();
    const rawList = Array.isArray(data?.reviews) ? data.reviews : [];
    return rawList.map((item: Record<string, unknown>) => normalizeNoteReview(item));
  }

  static async getReviewStats(
    options: { signal?: AbortSignal } = {}
  ): Promise<NoteReviewStats> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/notes/reviews/stats`, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) throw new Error('Unauthorized');
      throw new Error(`Failed to fetch review stats (${res.status})`);
    }

    const data = await res.json();
    return {
      total: Number(data?.stats?.total || 0),
      due: Number(data?.stats?.due || 0),
      upcoming: Number(data?.stats?.upcoming || 0),
      completed: Number(data?.stats?.completed || 0),
    };
  }

  static async submitReview(
    noteId: string,
    outcome: 'remembered' | 'struggled',
    options: { signal?: AbortSignal } = {}
  ): Promise<NoteReview> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(noteId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/notes/${encoded}/review`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ outcome }),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData?.error || `Failed to submit review (${res.status})`);
    }

    const data = await res.json();
    return normalizeNoteReview(data?.review || {});
  }

  static async updateReviewSettings(
    noteId: string,
    status: 'active' | 'paused' | 'completed',
    options: { signal?: AbortSignal } = {}
  ): Promise<NoteReview> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(noteId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/notes/${encoded}/review/settings`, {
      method: 'PUT',
      headers,
      body: JSON.stringify({ status }),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData?.error || `Failed to update review settings (${res.status})`);
    }

    const data = await res.json();
    return normalizeNoteReview(data?.review || {});
  }

  // ── Notes Export ────────────────────────────────────────────────────────────

  static async exportNotes(
    bookId?: string,
    format: string = 'markdown',
    options: { signal?: AbortSignal } = {}
  ): Promise<ExportNotesResult> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/notes/export`);
    if (bookId) url.searchParams.append('book_id', bookId.trim());
    url.searchParams.append('format', format);
    url.searchParams.append('json', 'true');

    const res = await this.fetchWithTimeout(url.toString(), {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) throw new Error('Unauthorized');
      throw new Error(`Failed to export notes (${res.status})`);
    }

    const data = await res.json();
    return {
      filename: String(data?.filename || 'libris_notes.md'),
      content: String(data?.content || ''),
      mime_type: String(data?.mime_type || 'text/markdown; charset=utf-8'),
      total: Number(data?.total || 0),
    };
  }

  // ── Learning Paths & Progress Intelligence ──────────────────────────────────

  static async getLearningPaths(
    status?: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningPath[]> {
    const headers = await this.getHeaders();
    let url = `${API_URL}/api/learning-paths`;
    if (status) url += `?status=${encodeURIComponent(status)}`;
    const res = await this.fetchWithTimeout(url, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) throw new Error('Unauthorized');
      throw new Error(`Failed to fetch learning paths (${res.status})`);
    }

    const data = await res.json();
    const rawList = Array.isArray(data?.paths) ? data.paths : [];
    return rawList.map((p: Record<string, unknown>) => normalizeLearningPath(p));
  }

  static async getLearningPathById(
    pathId: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningPath> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(pathId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning-paths/${encoded}`, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) throw new Error('Unauthorized');
      if (res.status === 404) throw new Error('Learning path not found');
      throw new Error(`Failed to fetch learning path (${res.status})`);
    }

    const data = await res.json();
    return normalizeLearningPath(data?.path || {});
  }

  static async createLearningPath(
    input: CreateLearningPathInput,
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningPath> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning-paths`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        title: input.title.trim(),
        description: input.description?.trim() || '',
        category: input.category?.trim() || '',
        book_ids: input.bookIds || [],
      }),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err?.error || `Failed to create learning path (${res.status})`);
    }

    const data = await res.json();
    return normalizeLearningPath(data?.path || {});
  }

  static async updateLearningPath(
    pathId: string,
    updates: { title?: string; description?: string; category?: string; status?: string },
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningPath> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(pathId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning-paths/${encoded}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify(updates),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err?.error || `Failed to update learning path (${res.status})`);
    }

    const data = await res.json();
    return normalizeLearningPath(data?.path || {});
  }

  static async deleteLearningPath(
    pathId: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<boolean> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(pathId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning-paths/${encoded}`, {
      method: 'DELETE',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      if (res.status === 401) throw new Error('Unauthorized');
      return false;
    }

    const data = await res.json().catch(() => ({}));
    return Boolean(data?.deleted || res.ok);
  }

  static async addBookToLearningPath(
    pathId: string,
    bookId: string,
    orderIndex?: number,
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningPath> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(pathId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning-paths/${encoded}/books`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ book_id: bookId.trim(), order_index: orderIndex }),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err?.error || `Failed to add book to learning path (${res.status})`);
    }

    const data = await res.json();
    return normalizeLearningPath(data?.path || {});
  }

  static async removeBookFromLearningPath(
    pathId: string,
    bookId: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningPath> {
    const headers = await this.getHeaders();
    const encPath = encodeURIComponent(pathId.trim());
    const encBook = encodeURIComponent(bookId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning-paths/${encPath}/books/${encBook}`, {
      method: 'DELETE',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err?.error || `Failed to remove book from learning path (${res.status})`);
    }

    const data = await res.json();
    return normalizeLearningPath(data?.path || {});
  }

  static async reorderLearningPathBooks(
    pathId: string,
    bookIds: string[],
    options: { signal?: AbortSignal } = {}
  ): Promise<LearningPath> {
    const headers = await this.getHeaders();
    const encoded = encodeURIComponent(pathId.trim());
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning-paths/${encoded}/reorder`, {
      method: 'PUT',
      headers,
      body: JSON.stringify({ book_ids: bookIds }),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err?.error || `Failed to reorder books (${res.status})`);
    }

    const data = await res.json();
    return normalizeLearningPath(data?.path || {});
  }

  static async getLearningPathSuggestions(
    category?: string,
    query?: string,
    limit: number = 10,
    options: { signal?: AbortSignal } = {}
  ): Promise<Book[]> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/learning-paths/suggestions`);
    if (category) url.searchParams.append('category', category.trim());
    if (query) url.searchParams.append('q', query.trim());
    url.searchParams.append('limit', String(limit));

    const res = await this.fetchWithTimeout(url.toString(), {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      return [];
    }

    const data = await res.json();
    const rawList = Array.isArray(data?.suggestions) ? data.suggestions : [];
    return normalizeBooks(rawList);
  }


  static async getKnowledgeGraph(
    params?: {
      focusId?: string;
      depth?: number;
      limit?: number;
      type?: string;
      relationshipType?: string;
    },
    options: { signal?: AbortSignal } = {}
  ): Promise<KnowledgeGraphData> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/knowledge-graph`);
    if (params?.focusId) url.searchParams.append('focus_id', params.focusId.trim());
    if (params?.depth) url.searchParams.append('depth', String(params.depth));
    if (params?.limit) url.searchParams.append('limit', String(params.limit));
    if (params?.type) url.searchParams.append('type', params.type.trim());
    if (params?.relationshipType) url.searchParams.append('relationship_type', params.relationshipType.trim());

    const res = await this.fetchWithTimeout(url.toString(), {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch knowledge graph: ${res.status}`);
    }

    const data = await res.json();
    return normalizeKnowledgeGraph(data);
  }

  static async createRelationship(
    input: CreateRelationshipInput,
    options: { signal?: AbortSignal } = {}
  ): Promise<KnowledgeEdge> {
    const headers = await this.getHeaders();
    const url = `${API_URL}/api/knowledge-graph/relationships`;

    const res = await this.fetchWithTimeout(url, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        source_id: input.sourceId,
        source_type: input.sourceType,
        target_id: input.targetId,
        target_type: input.targetType,
        relationship_type: input.relationshipType,
        source: input.source || 'user_explicit',
        evidence_ref: input.evidenceRef,
        confidence: input.confidence || 'high',
        metadata: input.metadata || {},
      }),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData.error || `Failed to create relationship: ${res.status}`);
    }

    const data = await res.json();
    return normalizeKnowledgeEdge(data.relationship);
  }

  static async getRelationshipById(
    id: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<KnowledgeEdge | null> {
    const headers = await this.getHeaders();
    const url = `${API_URL}/api/knowledge-graph/relationships/${encodeURIComponent(id)}`;

    const res = await this.fetchWithTimeout(url, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (res.status === 404) return null;
    if (!res.ok) {
      throw new Error(`Failed to fetch relationship: ${res.status}`);
    }

    const data = await res.json();
    return normalizeKnowledgeEdge(data.relationship);
  }

  static async updateRelationship(
    id: string,
    updates: { relationshipType?: string; confidence?: string; metadata?: Record<string, unknown> },
    options: { signal?: AbortSignal } = {}
  ): Promise<KnowledgeEdge | null> {
    const headers = await this.getHeaders();
    const url = `${API_URL}/api/knowledge-graph/relationships/${encodeURIComponent(id)}`;

    const payload: Record<string, unknown> = {};
    if (updates.relationshipType) payload.relationship_type = updates.relationshipType;
    if (updates.confidence) payload.confidence = updates.confidence;
    if (updates.metadata) payload.metadata = updates.metadata;

    const res = await this.fetchWithTimeout(url, {
      method: 'PUT',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      cache: 'no-store',
      signal: options.signal,
    });

    if (res.status === 404) return null;
    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData.error || `Failed to update relationship: ${res.status}`);
    }

    const data = await res.json();
    return normalizeKnowledgeEdge(data.relationship);
  }

  static async deleteRelationship(
    id: string,
    options: { signal?: AbortSignal } = {}
  ): Promise<boolean> {
    const headers = await this.getHeaders();
    const url = `${API_URL}/api/knowledge-graph/relationships/${encodeURIComponent(id)}`;

    const res = await this.fetchWithTimeout(url, {
      method: 'DELETE',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (res.status === 404) return false;
    if (!res.ok) {
      throw new Error(`Failed to delete relationship: ${res.status}`);
    }

    return true;
  }

  static async getNodeNeighbors(
    nodeId: string,
    params?: { depth?: number; limit?: number },
    options: { signal?: AbortSignal } = {}
  ): Promise<KnowledgeGraphData> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/knowledge-graph/nodes/${encodeURIComponent(nodeId)}/neighbors`);
    if (params?.depth) url.searchParams.append('depth', String(params.depth));
    if (params?.limit) url.searchParams.append('limit', String(params.limit));

    const res = await this.fetchWithTimeout(url.toString(), {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch node neighbors: ${res.status}`);
    }

    const data = await res.json();
    return normalizeKnowledgeGraph(data);
  }
  // ── Sprint 28: Learning Outcomes Intelligence ───────────────────────────

  static async getLearningOverview(options: { signal?: AbortSignal } = {}): Promise<LearningProgress> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning/overview`, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch learning overview: ${res.status}`);
    }

    const data = await res.json();
    return normalizeLearningProgress(data.progress || data);
  }

  static async getLearningQueue(
    params?: { concept?: string; pathId?: string; limit?: number },
    options: { signal?: AbortSignal } = {}
  ): Promise<ReviewItem[]> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/learning/queue`);
    if (params?.concept) url.searchParams.append('concept', params.concept);
    if (params?.pathId) url.searchParams.append('path_id', params.pathId);
    if (params?.limit) url.searchParams.append('limit', String(params.limit));

    const res = await this.fetchWithTimeout(url.toString(), {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch learning review queue: ${res.status}`);
    }

    const data = await res.json();
    const queue = Array.isArray(data.queue) ? data.queue : [];
    return queue.map(normalizeReviewItem);
  }

  static async getLearningItem(itemId: string, options: { signal?: AbortSignal } = {}): Promise<ReviewItem | null> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning/items/${encodeURIComponent(itemId)}`, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (res.status === 404) return null;
    if (!res.ok) {
      throw new Error(`Failed to fetch learning item: ${res.status}`);
    }

    const data = await res.json();
    return data.item ? normalizeReviewItem(data.item) : null;
  }

  static async createLearningItem(
    input: CreateReviewItemInput,
    options: { signal?: AbortSignal } = {}
  ): Promise<ReviewItem> {
    const headers = await this.getHeaders();
    const payload = {
      title: input.title,
      concept: input.concept,
      question: input.question,
      answer: input.answer,
      explanation: input.explanation || '',
      source_type: input.sourceType || 'user_created',
      source_id: input.sourceId,
      book_id: input.bookId,
      path_id: input.pathId,
      metadata: input.metadata || {},
    };

    const res = await this.fetchWithTimeout(`${API_URL}/api/learning/items`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `Failed to create review item: ${res.status}`);
    }

    const data = await res.json();
    return normalizeReviewItem(data.item);
  }

  static async updateLearningItem(
    itemId: string,
    updates: Partial<CreateReviewItemInput> & { status?: string },
    options: { signal?: AbortSignal } = {}
  ): Promise<ReviewItem> {
    const headers = await this.getHeaders();
    const payload: Record<string, unknown> = {};
    if (updates.title !== undefined) payload.title = updates.title;
    if (updates.concept !== undefined) payload.concept = updates.concept;
    if (updates.question !== undefined) payload.question = updates.question;
    if (updates.answer !== undefined) payload.answer = updates.answer;
    if (updates.explanation !== undefined) payload.explanation = updates.explanation;
    if (updates.status !== undefined) payload.status = updates.status;

    const res = await this.fetchWithTimeout(`${API_URL}/api/learning/items/${encodeURIComponent(itemId)}`, {
      method: 'PUT',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      throw new Error(`Failed to update review item: ${res.status}`);
    }

    const data = await res.json();
    return normalizeReviewItem(data.item);
  }

  static async deleteLearningItem(itemId: string, options: { signal?: AbortSignal } = {}): Promise<boolean> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning/items/${encodeURIComponent(itemId)}`, {
      method: 'DELETE',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (res.status === 404) return false;
    if (!res.ok) {
      throw new Error(`Failed to delete review item: ${res.status}`);
    }
    return true;
  }

  static async submitLearningAttempt(
    input: SubmitReviewAttemptInput,
    options: { signal?: AbortSignal } = {}
  ): Promise<{ item: ReviewItem; attempt: ReviewAttempt; nextReviewAt: string; intervalDays: number; newStage: number }> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(
      `${API_URL}/api/learning/items/${encodeURIComponent(input.itemId)}/attempt`,
      {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          outcome: input.outcome,
          response_text: input.responseText || '',
        }),
        cache: 'no-store',
        signal: options.signal,
      }
    );

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `Failed to submit review attempt: ${res.status}`);
    }

    const data = await res.json();
    return {
      item: normalizeReviewItem(data.item),
      attempt: normalizeReviewAttempt(data.attempt),
      nextReviewAt: data.next_review_at || data.nextReviewAt,
      intervalDays: data.interval_days || data.intervalDays,
      newStage: data.new_stage || data.newStage,
    };
  }

  static async getLearningHistory(
    params?: { itemId?: string; limit?: number; offset?: number },
    options: { signal?: AbortSignal } = {}
  ): Promise<{ attempts: ReviewAttempt[]; total: number }> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/learning/history`);
    if (params?.itemId) url.searchParams.append('item_id', params.itemId);
    if (params?.limit) url.searchParams.append('limit', String(params.limit));
    if (params?.offset) url.searchParams.append('offset', String(params.offset));

    const res = await this.fetchWithTimeout(url.toString(), {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch learning history: ${res.status}`);
    }

    const data = await res.json();
    const attempts = Array.isArray(data.attempts) ? data.attempts.map(normalizeReviewAttempt) : [];
    return {
      attempts,
      total: typeof data.total === 'number' ? data.total : attempts.length,
    };
  }

  static async getLearningConcepts(options: { signal?: AbortSignal } = {}): Promise<DifficultConcept[]> {
    const headers = await this.getHeaders();
    const res = await this.fetchWithTimeout(`${API_URL}/api/learning/concepts`, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: options.signal,
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch learning concepts: ${res.status}`);
    }

    const data = await res.json();
    const rawConcepts = Array.isArray(data.concepts) ? data.concepts : [];
    return rawConcepts.map((c: Record<string, unknown>) => ({
      concept: String(c.concept || ''),
      totalItems: Number(c.total_items || c.totalItems || 0),
      totalAttempts: Number(c.total_attempts || c.totalAttempts || 0),
      successfulRecalls: Number(c.successful_recalls || c.successfulRecalls || 0),
      struggledRecalls: Number(c.struggled_recalls || c.struggledRecalls || 0),
      retentionRate: Number(c.retention_rate !== undefined ? c.retention_rate : c.retentionRate || 0),
      averageStage: Number(c.average_stage || c.averageStage || 1),
      dueItems: Number(c.due_items || c.dueItems || 0),
      needsReview: Boolean(c.needs_review !== undefined ? c.needs_review : c.needsReview),
    }));
  }
}
