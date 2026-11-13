'use server';

import { revalidatePath } from 'next/cache';
import { ApiService } from '@/lib/api';
import { createClient } from '@/lib/supabase/server';
import type {
  CreateReviewItemInput,
  DifficultConcept,
  LearningProgress,
  ReviewAttempt,
  ReviewItem,
  SubmitReviewAttemptInput,
} from '@/types';

function safeRevalidatePath(path: string) {
  try {
    revalidatePath(path);
  } catch {
    // Graceful no-op in test environments without Next.js request context
  }
}

export async function getLearningOverviewAction(): Promise<{
  success: boolean;
  progress?: LearningProgress;
  error?: string;
}> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const progress = await ApiService.getLearningOverview();
    return { success: true, progress };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load learning overview';
    return { success: false, error: msg };
  }
}

export async function getLearningQueueAction(params?: {
  concept?: string;
  limit?: number;
}): Promise<{ success: boolean; queue?: ReviewItem[]; error?: string }> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const queue = await ApiService.getLearningQueue(params);
    return { success: true, queue };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load review queue';
    return { success: false, error: msg };
  }
}

export async function getLearningItemAction(
  itemId: string
): Promise<{ success: boolean; item?: ReviewItem | null; error?: string }> {
  if (!itemId || !itemId.trim()) {
    return { success: false, error: 'itemId is required' };
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

    const item = await ApiService.getLearningItem(itemId.trim());
    return { success: true, item };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load review item';
    return { success: false, error: msg };
  }
}

export async function createLearningItemAction(
  input: CreateReviewItemInput
): Promise<{ success: boolean; item?: ReviewItem; error?: string }> {
  if (!input.title?.trim() || !input.concept?.trim() || !input.question?.trim() || !input.answer?.trim()) {
    return { success: false, error: 'title, concept, question, and answer are required' };
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

    const item = await ApiService.createLearningItem(input);
    safeRevalidatePath('/learning');
    return { success: true, item };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to create review item';
    return { success: false, error: msg };
  }
}

export async function updateLearningItemAction(
  itemId: string,
  updates: Partial<CreateReviewItemInput> & { status?: string }
): Promise<{ success: boolean; item?: ReviewItem | null; error?: string }> {
  if (!itemId || !itemId.trim()) {
    return { success: false, error: 'itemId is required' };
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

    const item = await ApiService.updateLearningItem(itemId.trim(), updates);
    safeRevalidatePath('/learning');
    return { success: true, item };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to update review item';
    return { success: false, error: msg };
  }
}

export async function deleteLearningItemAction(
  itemId: string
): Promise<{ success: boolean; error?: string }> {
  if (!itemId || !itemId.trim()) {
    return { success: false, error: 'itemId is required' };
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

    const deleted = await ApiService.deleteLearningItem(itemId.trim());
    safeRevalidatePath('/learning');
    return { success: deleted };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to delete review item';
    return { success: false, error: msg };
  }
}

export async function submitLearningAttemptAction(
  input: SubmitReviewAttemptInput
): Promise<{
  success: boolean;
  result?: {
    item: ReviewItem;
    attempt: ReviewAttempt;
    nextReviewAt: string;
    intervalDays: number;
    newStage: number;
  };
  error?: string;
}> {
  if (!input.itemId?.trim() || !input.outcome) {
    return { success: false, error: 'itemId and outcome are required' };
  }

  if (input.outcome !== 'remembered' && input.outcome !== 'struggled') {
    return { success: false, error: "outcome must be 'remembered' or 'struggled'" };
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

    const result = await ApiService.submitLearningAttempt(input);
    safeRevalidatePath('/learning');
    safeRevalidatePath('/favorites');
    safeRevalidatePath('/discovery');
    return { success: true, result };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to record review attempt';
    return { success: false, error: msg };
  }
}

export async function getLearningHistoryAction(params?: {
  itemId?: string;
  limit?: number;
  offset?: number;
}): Promise<{
  success: boolean;
  attempts?: ReviewAttempt[];
  total?: number;
  error?: string;
}> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const res = await ApiService.getLearningHistory(params);
    return { success: true, attempts: res.attempts, total: res.total };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load learning history';
    return { success: false, error: msg };
  }
}

export async function getLearningConceptsAction(): Promise<{
  success: boolean;
  concepts?: DifficultConcept[];
  error?: string;
}> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const concepts = await ApiService.getLearningConcepts();
    return { success: true, concepts };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load learning concepts';
    return { success: false, error: msg };
  }
}

