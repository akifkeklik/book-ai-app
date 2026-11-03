'use server';

import { ApiService } from '@/lib/api';
import { updateLibraryItemStatus } from './library';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

function safeRevalidatePath(path: string) {
  try {
    revalidatePath(path);
  } catch {
    // Gracefully ignore when executed outside Next.js request lifecycle (e.g. testing)
  }
}

export async function submitFeedbackAction(
  bookId: string,
  interaction: 'like' | 'dislike' | 'favorite' | 'want_to_read' | 'reading' | 'finished' | 'clear' | 'remove'
): Promise<{ success: boolean; error?: string }> {
  try {
    if (interaction === 'favorite') {
      return await updateLibraryItemStatus(bookId, 'favorite');
    }

    const success = await ApiService.submitFeedback(bookId, interaction);
    if (success) {
      safeRevalidatePath('/');
      safeRevalidatePath('/catalog');
      safeRevalidatePath('/favorites');
      safeRevalidatePath('/discovery/personalized');
      safeRevalidatePath(`/book/${bookId}`);
    }
    return { success };
  } catch (e: unknown) {
    return { success: false, error: e instanceof Error ? e.message : 'Failed to submit feedback' };
  }
}

export async function trackActivityAction(
  bookId: string,
  action: string = 'view'
): Promise<{ success: boolean; error?: string }> {
  try {
    const supabase = await createClient();
    let hasUser = false;
    try {
      if (typeof supabase?.auth?.getUser === 'function') {
        const { data: { user }, error } = await supabase.auth.getUser();
        hasUser = !!user && !error;
      }
    } catch {
      hasUser = false;
    }

    if (!hasUser) {
      // Early return: unauthenticated views should not generate 401s on backend /api/track
      return { success: false, error: 'Unauthorized: Session required for activity tracking' };
    }

    const success = await ApiService.trackActivity(bookId, action);
    return { success };
  } catch (e: unknown) {
    return { success: false, error: e instanceof Error ? e.message : 'Failed to track activity' };
  }
}

export async function getUserPreferencesAction(): Promise<{
  success: boolean;
  preferredGenres: string[];
  preferredAuthors: string[];
  error?: string;
}> {
  try {
    const supabase = await createClient();
    let hasUser = false;
    try {
      if (typeof supabase?.auth?.getUser === 'function') {
        const { data: { user }, error } = await supabase.auth.getUser();
        hasUser = !!user && !error;
      }
    } catch {
      hasUser = false;
    }

    if (!hasUser) {
      return { success: false, preferredGenres: [], preferredAuthors: [], error: 'Unauthorized' };
    }

    const prefs = await ApiService.getUserPreferences();
    return { success: true, ...prefs };
  } catch (e: unknown) {
    return {
      success: false,
      preferredGenres: [],
      preferredAuthors: [],
      error: e instanceof Error ? e.message : 'Failed to load preferences',
    };
  }
}

export async function updateUserPreferencesAction(
  genres: string[],
  authors?: string[]
): Promise<{ success: boolean; error?: string }> {
  try {
    const supabase = await createClient();
    let hasUser = false;
    try {
      if (typeof supabase?.auth?.getUser === 'function') {
        const { data: { user }, error } = await supabase.auth.getUser();
        hasUser = !!user && !error;
      }
    } catch {
      hasUser = false;
    }

    if (!hasUser) {
      return { success: false, error: 'Unauthorized' };
    }

    const success = await ApiService.updateUserPreferences(genres, authors);
    if (success) {
      safeRevalidatePath('/');
      safeRevalidatePath('/settings');
      safeRevalidatePath('/catalog');
    }
    return { success };
  } catch (e: unknown) {
    return { success: false, error: e instanceof Error ? e.message : 'Failed to update preferences' };
  }
}
