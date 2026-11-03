import type { Book, LibraryItem } from '@/types';

export type ReadingGoalType = 'annual' | 'weekly' | 'category';

export interface ReadingGoal {
  type: ReadingGoalType;
  target: number;
  category?: string;
}

export interface ReadingProgressItem {
  bookId: string;
  title: string;
  currentPage: number;
  totalPages: number | null;
  percent: number | null;
}

export interface ReadingJourneyResult {
  safeGoal: number;
  completedCount: number;
  readingCount: number;
  wantToReadCount: number;
  favoriteCount: number;
  progressPercent: number;
  isGoalReached: boolean;
  readingProgress: ReadingProgressItem[];
  readingBooks: LibraryItem[];
  wantToReadBooks: LibraryItem[];
  completedBooks: LibraryItem[];
}

/**
 * Pure calculation function for reading journey metrics.
 * Ensures data accuracy:
 * - Completed count strictly requires status === 'finished'
 * - Favorites never inflate reading progress
 * - Bounded percentage calculation without division by zero
 */
export function calculateReadingJourney(
  items: LibraryItem[],
  goalInput: ReadingGoal | number = 20
): ReadingJourneyResult {
  const goal: ReadingGoal =
    typeof goalInput === 'number'
      ? { type: 'annual', target: goalInput }
      : goalInput || { type: 'annual', target: 20 };

  const defaultTarget = goal.type === 'weekly' ? 1 : goal.type === 'category' ? 5 : 20;
  const rawTarget = goal.target;
  const safeGoal = Math.max(
    1,
    isNaN(rawTarget) || rawTarget <= 0 || !isFinite(rawTarget) ? defaultTarget : Math.min(500, Math.floor(rawTarget))
  );

  // Group books by strictly validated statuses
  const allFinished = items.filter((item) => item.status === 'finished');
  const readingBooks = items.filter((item) => item.status === 'reading');
  const wantToReadBooks = items.filter((item) => item.status === 'want_to_read');
  const favoriteBooks = items.filter((item) => item.status === 'favorite' || item.isFavorite);

  // If topic/category goal is active, filter completed books by category
  const targetCategory = goal.type === 'category' && goal.category ? goal.category.trim().toLowerCase() : null;
  const matchingFinished = targetCategory
    ? allFinished.filter((item) => (item.book.categories || '').toLowerCase().includes(targetCategory))
    : allFinished;

  const completedCount = matchingFinished.length;
  const progressPercent = Math.min(100, Math.max(0, Math.round((completedCount / safeGoal) * 100)));
  const isGoalReached = completedCount >= safeGoal;

  // Active reading page calculations
  const readingProgress: ReadingProgressItem[] = readingBooks.map((item) => {
    const totalPages =
      typeof item.book?.pageCount === 'number' && item.book.pageCount > 0 ? item.book.pageCount : null;
    const currentPage =
      typeof item.currentPage === 'number' && item.currentPage > 0 ? item.currentPage : 0;
    const percent = totalPages
      ? Math.min(100, Math.max(0, Math.round((currentPage / totalPages) * 100)))
      : null;
    return {
      bookId: item.bookId,
      title: item.book?.title || 'Unknown Title',
      currentPage,
      totalPages,
      percent,
    };
  });

  return {
    safeGoal,
    completedCount,
    readingCount: readingBooks.length,
    wantToReadCount: wantToReadBooks.length,
    favoriteCount: favoriteBooks.length,
    progressPercent,
    isGoalReached,
    readingProgress,
    readingBooks,
    wantToReadBooks,
    completedBooks: allFinished,
  };
}

/**
 * Determines the next recommended book from the personalized recommendations.
 * - Filters out books that are currently being read or already completed.
 * - Prioritizes books already in want_to_read if they appear in recommendations.
 * - Otherwise picks the top recommendation with a genuine attribution/reason.
 */
export function determineNextBook(
  recommendations: Book[],
  libraryItems: LibraryItem[]
): Book | null {
  if (!recommendations || recommendations.length === 0) return null;

  const readingOrFinishedIsbns = new Set(
    libraryItems
      .filter((i) => i.status === 'reading' || i.status === 'finished')
      .map((i) => i.bookId)
  );

  const wantToReadIsbns = new Set(
    libraryItems.filter((i) => i.status === 'want_to_read').map((i) => i.bookId)
  );

  // 1. First priority: candidate in want_to_read that appears in recommendations
  for (const book of recommendations) {
    if (wantToReadIsbns.has(book.isbn13) && !readingOrFinishedIsbns.has(book.isbn13)) {
      return book;
    }
  }

  // 2. Second priority: top recommended book that isn't already active/completed
  for (const book of recommendations) {
    if (!readingOrFinishedIsbns.has(book.isbn13)) {
      return book;
    }
  }

  return null;
}

const STORAGE_KEY_V2 = 'libris_reading_goal_v2';
const STORAGE_KEY_LEGACY = 'libris_reading_goal_annual';

/**
 * Safely loads the client-side reading goal from localStorage.
 * Transparently indicates local persistence per instructions.
 */
export function loadSavedReadingGoal(): ReadingGoal {
  if (typeof window === 'undefined') {
    return { type: 'annual', target: 20 };
  }

  try {
    const rawV2 = localStorage.getItem(STORAGE_KEY_V2);
    if (rawV2) {
      const parsed = JSON.parse(rawV2);
      if (
        parsed &&
        typeof parsed === 'object' &&
        (parsed.type === 'annual' || parsed.type === 'weekly' || parsed.type === 'category') &&
        typeof parsed.target === 'number' &&
        parsed.target > 0 &&
        parsed.target <= 500
      ) {
        return {
          type: parsed.type,
          target: Math.floor(parsed.target),
          category: typeof parsed.category === 'string' ? parsed.category : undefined,
        };
      }
    }

    // Fallback to legacy annual goal
    const rawLegacy = localStorage.getItem(STORAGE_KEY_LEGACY);
    if (rawLegacy) {
      const parsedLegacy = parseInt(rawLegacy, 10);
      if (!isNaN(parsedLegacy) && parsedLegacy > 0 && parsedLegacy <= 500) {
        return { type: 'annual', target: parsedLegacy };
      }
    }
  } catch {
    // Return default on local storage parse issues
  }

  return { type: 'annual', target: 20 };
}

/**
 * Safely persists the client-side reading goal to localStorage.
 */
export function saveReadingGoal(goal: ReadingGoal): void {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(STORAGE_KEY_V2, JSON.stringify(goal));
    if (goal.type === 'annual') {
      localStorage.setItem(STORAGE_KEY_LEGACY, String(goal.target));
    }
  } catch {
    // Ignore quota or disabled storage
  }
}
