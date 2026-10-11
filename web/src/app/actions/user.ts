'use server';

import { ApiService } from '@/lib/api';
import { revalidatePath } from 'next/cache';

export async function submitFeedbackAction(
  bookId: string,
  interaction: 'like' | 'dislike' | 'favorite' | 'want_to_read' | 'finished'
): Promise<{ success: boolean; error?: string }> {
  try {
    const success = await ApiService.submitFeedback(bookId, interaction);
    if (success) {
      revalidatePath('/');
      revalidatePath('/catalog');
      revalidatePath(`/book/${bookId}`);
    }
    return { success };
  } catch (e: unknown) {
    return { success: false, error: e instanceof Error ? e.message : 'Failed to submit feedback' };
  }
}

export async function trackActivityAction(bookId: string, action: string = 'view'): Promise<{ success: boolean; error?: string }> {
  try {
    const success = await ApiService.trackActivity(bookId, action);
    return { success };
  } catch (e: unknown) {
    return { success: false, error: e instanceof Error ? e.message : 'Failed to track activity' };
  }
}
