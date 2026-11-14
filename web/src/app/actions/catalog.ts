'use server';

import { ApiService } from '@/lib/api';
import type { Book, BookLookupResult, NewCatalogBook } from '@/types';
import { createClient } from '@/lib/supabase/server';

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



async function isSignedIn(): Promise<boolean> {
  try {
    const supabase = await createClient();
    const { data: { user }, error } = await supabase.auth.getUser();
    return !!user && !error;
  } catch {
    return false;
  }
}

/** Candidates to pre-fill the add-a-book form. */
export async function lookupBooksAction(query: string): Promise<{ success: boolean; results: BookLookupResult[]; error?: string }> {
  const trimmed = (query || '').trim();
  if (trimmed.length < 2) return { success: true, results: [] };
  if (trimmed.length > 200) return { success: false, results: [], error: 'Query is too long' };
  if (!(await isSignedIn())) return { success: false, results: [], error: 'Unauthorized' };
  try {
    return { success: true, results: await ApiService.lookupBooks(trimmed) };
  } catch (err: unknown) {
    return { success: false, results: [], error: err instanceof Error ? err.message : 'Lookup failed' };
  }
}

/** Adds a book that is missing from the catalog and returns its catalog id. */
export async function addCatalogBookAction(
  input: NewCatalogBook
): Promise<{ success: boolean; isbn13?: string; created?: boolean; persisted?: boolean; error?: string }> {
  if (!input?.title?.trim() || !input?.authors?.trim()) {
    return { success: false, error: 'Title and author are required' };
  }
  if (!(await isSignedIn())) return { success: false, error: 'Unauthorized' };
  try {
    const { book, created, persisted } = await ApiService.addCatalogBook({
      ...input,
      title: input.title.trim(),
      authors: input.authors.trim(),
    });
    return { success: true, isbn13: book.isbn13, created, persisted };
  } catch (err: unknown) {
    return { success: false, error: err instanceof Error ? err.message : 'Failed to add book' };
  }
}
