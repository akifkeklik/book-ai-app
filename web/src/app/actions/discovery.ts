'use server';

import { ApiService } from '@/lib/api';
import { createClient } from '@/lib/supabase/server';
import { submitFeedbackAction } from './user';
import type { Book } from '@/types';

export interface PersonalizedDiscoveryResult {
  success: boolean;
  books: Book[];
  isAuthenticated: boolean;
  isColdStart?: boolean;
  evidenceCoverage?: 'cold_start' | 'emerging' | 'established';
  error?: string;
}

/**
 * Fetches personalized recommendations for the authenticated user.
 * Supports optional category scoping, completed-book filtering, and cold-start metadata.
 */
export async function getPersonalizedRecommendationsAction(
  limit: number = 24,
  category?: string,
  excludeCompleted?: boolean
): Promise<PersonalizedDiscoveryResult> {
  try {
    const supabase = await createClient();
    let hasUser = false;

    try {
      if (typeof supabase?.auth?.getUser === 'function') {
        const {
          data: { user },
          error: authError,
        } = await supabase.auth.getUser();
        hasUser = !!user && !authError;
      }
    } catch {
      hasUser = false;
    }

    if (!hasUser) {
      return {
        success: false,
        books: [],
        isAuthenticated: false,
        error: 'Unauthorized',
      };
    }

    const result = await ApiService.getPersonalizedRecommendationsWithMeta(limit, {
      category,
      excludeCompleted,
    });
    return {
      success: true,
      books: result.books,
      isAuthenticated: true,
      isColdStart: result.isColdStart,
      evidenceCoverage: result.evidenceCoverage,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to fetch recommendations';
    const isUnauth = message.toLowerCase().includes('unauthorized') || message.includes('401');

    return {
      success: false,
      books: [],
      isAuthenticated: !isUnauth,
      error: message,
    };
  }
}

/**
 * Resets user personalization preferences and learning signals.
 */
export async function resetPersonalizationAction(): Promise<{ success: boolean; error?: string }> {
  try {
    const supabase = await createClient();
    let hasUser = false;
    try {
      if (typeof supabase?.auth?.getUser === 'function') {
        const {
          data: { user },
          error: authError,
        } = await supabase.auth.getUser();
        hasUser = !!user && !authError;
      }
    } catch {
      hasUser = false;
    }
    if (!hasUser) {
      return { success: false, error: 'Unauthorized' };
    }
    const ok = await ApiService.resetPersonalization();
    return { success: ok };
  } catch (err: unknown) {
    return { success: false, error: err instanceof Error ? err.message : 'Failed to reset personalization' };
  }
}

/**
 * Submits negative relevance feedback ('dislike') when the user dismisses a recommendation.
 * Automatically triggers server-side cache revalidation across discovery, catalog, and home.
 */
export async function dismissRecommendationAction(
  bookId: string
): Promise<{ success: boolean; error?: string }> {
  if (!bookId || typeof bookId !== 'string') {
    return { success: false, error: 'Invalid book ID' };
  }
  return await submitFeedbackAction(bookId, 'dislike');
}
