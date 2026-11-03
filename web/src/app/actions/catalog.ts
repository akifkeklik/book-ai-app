'use server';

import { ApiService } from '@/lib/api';
import type { Book } from '@/types';

/**
 * Server action to search catalog for Spotlight Search.
 * Keeps server-only dependencies and API configuration safely on the server side.
 */
export async function searchCatalogAction(query: string, limit: number = 10): Promise<{ success: boolean; books: Book[]; error?: string }> {
  const trimmed = (query || '').trim();
  if (!trimmed) {
    return { success: true, books: [] };
  }

  try {
    const res = await ApiService.getBooks({
      query: trimmed,
      per_page: limit,
    });
    return {
      success: true,
      books: res.books || [],
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to query catalog';
    return {
      success: false,
      books: [],
      error: message,
    };
  }
}

export async function fetchCatalogPageAction(params: {
  page: number;
  per_page?: number;
  category?: string;
  query?: string;
  sort?: string;
  order?: 'asc' | 'desc';
  min_rating?: number;
}): Promise<{ success: boolean; data?: { books: Book[]; total: number; total_pages: number }; error?: string }> {
  try {
    const res = await ApiService.getBooks(params);
    return {
      success: true,
      data: res,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to fetch catalog page';
    return {
      success: false,
      error: message,
    };
  }
}

