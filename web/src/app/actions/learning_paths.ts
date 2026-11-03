'use server';

import { revalidatePath } from 'next/cache';
import { ApiService } from '@/lib/api';
import { createClient } from '@/lib/supabase/server';
import type { CreateLearningPathInput, LearningPath, Book } from '@/types';

function safeRevalidatePath(path: string) {
  try {
    revalidatePath(path);
  } catch {
    // Graceful no-op in test environments without Next.js request context
  }
}

export async function getLearningPathsAction(
  status?: string
): Promise<{ success: boolean; paths: LearningPath[]; error?: string }> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, paths: [], error: 'Unauthorized' };
    }

    const paths = await ApiService.getLearningPaths(status);
    return { success: true, paths };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load learning paths';
    return { success: false, paths: [], error: msg };
  }
}

export async function getLearningPathDetailAction(
  pathId: string
): Promise<{ success: boolean; path?: LearningPath; error?: string }> {
  if (!pathId || !pathId.trim()) {
    return { success: false, error: 'pathId is required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const path = await ApiService.getLearningPathById(pathId.trim());
    return { success: true, path };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load learning path';
    return { success: false, error: msg };
  }
}

export async function createLearningPathAction(
  input: CreateLearningPathInput
): Promise<{ success: boolean; path?: LearningPath; error?: string }> {
  if (!input || !input.title || !input.title.trim()) {
    return { success: false, error: 'Title is required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const path = await ApiService.createLearningPath(input);
    safeRevalidatePath('/discovery');
    safeRevalidatePath('/learning-paths');
    return { success: true, path };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to create learning path';
    return { success: false, error: msg };
  }
}

export async function updateLearningPathAction(
  pathId: string,
  updates: { title?: string; description?: string; category?: string; status?: string }
): Promise<{ success: boolean; path?: LearningPath; error?: string }> {
  if (!pathId || !pathId.trim()) {
    return { success: false, error: 'pathId is required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const path = await ApiService.updateLearningPath(pathId.trim(), updates);
    safeRevalidatePath('/discovery');
    safeRevalidatePath('/learning-paths');
    return { success: true, path };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to update learning path';
    return { success: false, error: msg };
  }
}

export async function deleteLearningPathAction(
  pathId: string
): Promise<{ success: boolean; error?: string }> {
  if (!pathId || !pathId.trim()) {
    return { success: false, error: 'pathId is required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const ok = await ApiService.deleteLearningPath(pathId.trim());
    safeRevalidatePath('/discovery');
    safeRevalidatePath('/learning-paths');
    return { success: ok };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to delete learning path';
    return { success: false, error: msg };
  }
}

export async function addBookToLearningPathAction(
  pathId: string,
  bookId: string,
  orderIndex?: number
): Promise<{ success: boolean; path?: LearningPath; error?: string }> {
  if (!pathId || !pathId.trim() || !bookId || !bookId.trim()) {
    return { success: false, error: 'pathId and bookId are required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const path = await ApiService.addBookToLearningPath(pathId.trim(), bookId.trim(), orderIndex);
    safeRevalidatePath('/discovery');
    safeRevalidatePath('/learning-paths');
    return { success: true, path };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to add book to learning path';
    return { success: false, error: msg };
  }
}

export async function removeBookFromLearningPathAction(
  pathId: string,
  bookId: string
): Promise<{ success: boolean; path?: LearningPath; error?: string }> {
  if (!pathId || !pathId.trim() || !bookId || !bookId.trim()) {
    return { success: false, error: 'pathId and bookId are required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const path = await ApiService.removeBookFromLearningPath(pathId.trim(), bookId.trim());
    safeRevalidatePath('/discovery');
    safeRevalidatePath('/learning-paths');
    return { success: true, path };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to remove book from learning path';
    return { success: false, error: msg };
  }
}

export async function reorderLearningPathBooksAction(
  pathId: string,
  bookIds: string[]
): Promise<{ success: boolean; path?: LearningPath; error?: string }> {
  if (!pathId || !pathId.trim() || !Array.isArray(bookIds)) {
    return { success: false, error: 'pathId and bookIds array are required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const path = await ApiService.reorderLearningPathBooks(pathId.trim(), bookIds);
    safeRevalidatePath('/discovery');
    safeRevalidatePath('/learning-paths');
    return { success: true, path };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to reorder books in learning path';
    return { success: false, error: msg };
  }
}

export async function getLearningPathSuggestionsAction(
  category?: string,
  query?: string,
  limit: number = 10
): Promise<{ success: boolean; suggestions: Book[]; error?: string }> {
  try {
    const suggestions = await ApiService.getLearningPathSuggestions(category, query, limit);
    return { success: true, suggestions };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to get suggestions';
    return { success: false, suggestions: [], error: msg };
  }
}

export async function getLearningPathRecommendationsAction(
  pathId: string,
  limit: number = 10,
  excludeCompleted: boolean = true
): Promise<{ success: boolean; recommendations: Book[]; error?: string }> {
  if (!pathId || !pathId.trim()) {
    return { success: false, recommendations: [], error: 'pathId is required' };
  }
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, recommendations: [], error: 'Unauthorized' };
    }

    const recommendations = await ApiService.getLearningPathRecommendations(pathId.trim(), limit, { excludeCompleted });
    return { success: true, recommendations };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to get path recommendations';
    return { success: false, recommendations: [], error: msg };
  }
}


