import { createClient } from './supabase/server';
import type { Book, Category, PaginatedResponse } from '@/types';

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
    } catch (e) {
      console.error('Failed to get session for API request:', e);
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
    params: { page?: number; per_page?: number; category?: string; query?: string } = {}
  ): Promise<PaginatedResponse<Book>> {
    const headers = await this.getHeaders();
    const url = new URL(`${API_URL}/api/books`);
    
    if (params.page) url.searchParams.append('page', params.page.toString());
    if (params.per_page) url.searchParams.append('per_page', params.per_page.toString());
    if (params.category) url.searchParams.append('category', params.category);
    
    // Use search endpoint if query is provided
    if (params.query) {
      const searchUrl = new URL(`${API_URL}/api/search`);
      searchUrl.searchParams.append('q', params.query);
      searchUrl.searchParams.append('limit', (params.per_page || 40).toString());
      
      const res = await fetch(searchUrl.toString(), { headers });
      if (!res.ok) throw new Error('Failed to search books');
      const data = await res.json();
      return {
        books: data.books || [],
        total: data.books?.length || 0,
        total_pages: 1
      };
    }

    const res = await fetch(url.toString(), { headers });
    if (!res.ok) throw new Error('Failed to fetch books');
    
    return res.json();
  }

  static async getBookByIsbn(isbn: string): Promise<Book | null> {
    const headers = await this.getHeaders();
    const res = await fetch(`${API_URL}/api/books/${isbn}`, { headers });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error('Failed to fetch book details');
    
    const data = await res.json();
    return data.book;
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
    return data.recommendations || [];
  }

  static async chatWithAI(query: string): Promise<{ answer: string; recommendations?: Book[] }> {
    const headers = await this.getHeaders();
    const res = await fetch(`${API_URL}/api/ai/chat`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ query })
    });
    
    if (!res.ok) throw new Error('Failed to chat with AI');
    
    return res.json();
  }
}
