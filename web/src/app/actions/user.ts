'use server';

import { ApiService } from '@/lib/api';

export async function submitFeedbackAction(bookId: string, interaction: 'like' | 'dislike'): Promise<{ success: boolean; error?: string }> {
  try {
    const success = await ApiService.submitFeedback(bookId, interaction);
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
