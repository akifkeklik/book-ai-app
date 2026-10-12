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

export interface AiChatResponse {
  answer: string;
  referencedBooks: Book[];
  recommendations?: Book[];
  status?: string;
}

export type LibraryCollectionStatus = 'favorite' | 'want_to_read' | 'reading' | 'finished';

export interface LibraryItem {
  id: string;
  bookId: string;
  status: LibraryCollectionStatus;
  addedAt: string;
  book: Book;
}
