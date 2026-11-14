export interface Book {
  isbn13: string;
  title: string;
  authors: string;
  categories: string;
  description: string;
  thumbnail: string;
  averageRating: number;
  ratingsCount: number;
  publishedDate: string;
  pageCount: number;
  
  // Recommendation fields
  similarityScore?: number;
  explanation?: string;
  explanationSourceBook?: string;
  recommendationReason?: string;
  explanationType?: string;
  confidence?: 'high' | 'medium' | 'cold_start';
  isColdStart?: boolean;
}

export interface RecommendationDiagnostics {
  engineVersion: string;
  candidateCount: number;
  filteredCount: number;
  isColdStart: boolean;
  evidenceCoverage: 'cold_start' | 'emerging' | 'established';
  fallbackReason?: string | null;
  latencyMs?: number;
}

export interface UserTasteProfile {
  userId: string;
  categoryAffinities: Record<string, number>;
  authorAffinities: Record<string, number>;
  preferredGenres: string[];
  preferredAuthors: string[];
  positiveSignalCount: number;
  negativeSignalCount: number;
  totalNotesCount: number;
  takeawayCount: number;
  retentionSummary: Record<string, number>;
  activeLearningPathsCount: number;
  evidenceCoverage: 'cold_start' | 'emerging' | 'established';
  profileVersion: string;
  computedAt?: string;
}

export interface Category {
  name: string;
  count: number;
}

export interface PaginatedResponse<T> {
  books: T[];
  total: number;
  total_pages: number;
}

export type AiActionType = 'SET_THEME' | 'SET_PALETTE' | 'SET_LANGUAGE' | 'NAVIGATE';

export interface AiAction {
  type: AiActionType;
  payload: Record<string, string>;
}

export interface AiChatResponse {
  answer: string;
  referencedBooks: Book[];
  recommendations?: Book[];
  status?: string;
  action?: AiAction | null;
}

export type LibraryCollectionStatus = 'favorite' | 'want_to_read' | 'reading' | 'finished';

export interface LibraryItem {
  id: string;
  bookId: string;
  status: LibraryCollectionStatus;
  isFavorite?: boolean;
  currentPage?: number;
  addedAt: string;
  book: Book;
}

export type NoteType = 'personal_note' | 'key_takeaway' | 'question';

/** Recall question created from a saved takeaway (returned with the note). */
export interface RecallItemPreview {
  id: string;
  question: string;
  nextReviewAt: string | null;
}

export interface LearningNote {
  id: string;
  userId: string;
  bookId: string;
  noteType: NoteType;
  content: string;
  createdAt: string;
  updatedAt: string;
  clientId?: string;
  reviewStage?: number;
  nextReviewAt?: string;
  isReviewDue?: boolean;
  book?: {
    isbn13?: string;
    title?: string;
    authors?: string;
    thumbnail?: string;
  };
}

export interface NoteReview {
  id: string;
  noteId: string;
  userId: string;
  stage: number;
  intervalDays: number;
  nextReviewAt: string;
  lastReviewedAt?: string | null;
  reviewCount: number;
  status: 'active' | 'completed' | 'paused';
  note?: LearningNote;
}

export interface NoteReviewStats {
  total: number;
  due: number;
  upcoming: number;
  completed: number;
}

export interface ExportNotesResult {
  filename: string;
  content: string;
  mime_type: string;
  total: number;
}

// ── Sprint 28: Learning Outcomes Intelligence ───────────────────────────

export interface ReviewItem {
  id: string;
  userId: string;
  title: string;
  concept: string;
  question: string;
  answer: string;
  explanation?: string;
  sourceType: 'user_note' | 'key_takeaway' | 'concept' | 'learning_path' | 'user_created' | 'book' | string;
  sourceId?: string | null;
  bookId?: string | null;
  stage: number;
  intervalDays: number;
  nextReviewAt?: string;
  lastReviewedAt?: string | null;
  totalReviews: number;
  successfulReviews: number;
  status: 'active' | 'paused' | 'archived' | string;
  metadata?: Record<string, unknown>;
  createdAt?: string;
  updatedAt?: string;
  book?: Book | null;
  priority?: number;
  recommendationReason?: string;
  recommendationReasonKey?: string;
}

export interface ReviewAttempt {
  id?: string;
  userId: string;
  itemId: string;
  outcome: 'remembered' | 'struggled';
  responseText?: string;
  isCorrect: boolean;
  stageBefore: number;
  stageAfter: number;
  reviewedAt?: string;
  createdAt?: string;
  itemTitle?: string;
  concept?: string;
  bookId?: string;
}

export interface DifficultConcept {
  concept: string;
  totalItems: number;
  totalAttempts: number;
  successfulRecalls: number;
  struggledRecalls: number;
  retentionRate: number;
  averageStage: number;
  dueItems: number;
  needsReview: boolean;
}

export interface LearningProgress {
  masteryScore: number;
  masteryLevel: 'insufficient_data' | 'novice' | 'practicing' | 'proficient' | 'mastered' | string;
  totalItems: number;
  reviewsDue: number;
  reviewsCompleted: number;
  successfulRecalls: number;
  struggledRecalls: number;
  retentionRate: number;
  conceptsCount: number;
  difficultConcepts: DifficultConcept[];
  recentActivity: ReviewAttempt[];
  activeStreakDays: number;
  algorithmVersion: string;
}

export interface CreateReviewItemInput {
  title: string;
  concept: string;
  question: string;
  answer: string;
  explanation?: string;
  sourceType?: string;
  sourceId?: string;
  bookId?: string;
  metadata?: Record<string, unknown>;
}

export interface SubmitReviewAttemptInput {
  itemId: string;
  outcome: 'remembered' | 'struggled';
  responseText?: string;
}
