import { createClient } from './supabase/server';
import type { Book, Category, PaginatedResponse, AiChatResponse } from '@/types';
import { normalizeBook, normalizeBooks } from './normalizers';

const API_URL = process.env.BACKEND_URL || 'http://localhost:5000';
const API_KEY = process.env.LIBRIS_API_KEY || '';

export class ApiService {
  private static async getHeaders(): Promise<HeadersInit> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-Api-Key': API_KEY,
    };

    try {
      const supabase = await createClient();
      const { data: { session } } = await supabase.auth.getSession();
      
      if (session?.access_token) {
        headers['Authorization'] = `Bearer ${session.access_token}`;
      }
    } catch {
      // Ignore: session is optional and request store may be absent in testing/static generation
    }

    return headers;
  }

  static async getCategories(): Promise<Category[]> {
    const headers = await this.getHeaders();
    const res = await fetch(`${API_URL}/api/categories`, { headers });
    if (!res.ok) throw new Error('Failed to fetch categories');
    
    const data = await res.json();
    return data.categories || [];
  }

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
    } = {}
  ): Promise<PaginatedResponse<Book>> {
    const headers = await this.getHeaders();
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

    const res = await fetch(url.toString(), { headers });
    if (!res.ok) throw new Error('Failed to fetch books');
    
    const data = await res.json();
    return {
      books: normalizeBooks(data?.books),
      total: typeof data?.total === 'number' ? data.total : (Array.isArray(data?.books) ? data.books.length : 0),
      total_pages: typeof data?.total_pages === 'number' ? data.total_pages : 1,
    };
  }

  static async getBookByIsbn(isbn: string): Promise<Book | null> {
    const headers = await this.getHeaders();
    const res = await fetch(`${API_URL}/api/books/${isbn}`, { headers });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error('Failed to fetch book details');
    
    const data = await res.json();
    return data?.book ? normalizeBook(data.book) : null;
  }

  static async getRecommendations(bookTitle: string, topN: number = 20): Promise<Book[]> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/recommend`);
    url.searchParams.append('book', bookTitle);
    url.searchParams.append('top_n', topN.toString());
    url.searchParams.append('hybrid', 'true');
    
    const res = await fetch(url.toString(), { headers });
    if (!res.ok) throw new Error('Failed to fetch recommendations');
    
    const data = await res.json();
    return normalizeBooks(data?.recommendations);
  }

  static async chatWithAI(query: string): Promise<AiChatResponse> {
    const headers = await this.getHeaders();
    const res = await fetch(`${API_URL}/api/ai/chat`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ query }),
    });
    
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

    return {
      answer: typeof data?.answer === 'string' ? data.answer : '',
      referencedBooks: normalizedBooks,
      recommendations: normalizedBooks,
      status: typeof data?.status === 'string' ? data.status : 'success',
    };
  }

  static async getPersonalizedRecommendations(limit: number = 10): Promise<Book[]> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/recommend/personalized`);
    url.searchParams.append('limit', limit.toString());
    
    const res = await fetch(url.toString(), { headers });
    if (!res.ok) throw new Error('Failed to fetch personalized recommendations');
    
    const data = await res.json();
    return normalizeBooks(data?.recommendations);
  }

  static async submitFeedback(
    bookId: string,
    interaction: 'like' | 'dislike' | 'favorite' | 'want_to_read' | 'finished'
  ): Promise<boolean> {
    const headers = await this.getHeaders();
    const res = await fetch(`${API_URL}/api/feedback`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ book_id: bookId, interaction })
    });
    return res.ok;
  }

  static async trackActivity(bookId: string, action: string = 'view'): Promise<boolean> {
    const headers = await this.getHeaders();
    const res = await fetch(`${API_URL}/api/track`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ book_id: bookId, action })
    });
    return res.ok;
  }
}
