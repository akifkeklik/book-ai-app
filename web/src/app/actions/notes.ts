'use server';

import { ApiService } from '@/lib/api';
import { createClient } from '@/lib/supabase/server';
import type { LearningNote, RecallItemPreview, NoteReview, NoteType } from '@/types';
import { revalidatePath } from 'next/cache';

function safeRevalidatePath(path: string) {
  try {
    revalidatePath(path);
  } catch {
    // Gracefully ignore when outside Next.js request lifecycle
  }
}

/**
 * Retrieves notes for a specific book for the authenticated user.
 */
export async function getBookNotes(bookId: string): Promise<{
  success: boolean;
  notes: LearningNote[];
  isAuthenticated: boolean;
  error?: string;
}> {
  if (!bookId || typeof bookId !== 'string' || !bookId.trim()) {
    return { success: false, notes: [], isAuthenticated: false, error: 'Invalid bookId' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, notes: [], isAuthenticated: false };
    }

    const result = await ApiService.getBookNotes(bookId.trim());
    return {
      success: true,
      notes: result,
      isAuthenticated: true,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to fetch notes';
    return {
      success: false,
      notes: [],
      isAuthenticated: false,
      error: msg,
    };
  }
}

/**
 * Creates a new learning note, key takeaway, or question for a book.
 */
export async function createNote(
  bookId: string,
  noteType: NoteType,
  content: string
): Promise<{
  success: boolean;
  note?: LearningNote;
  recallItem?: RecallItemPreview | null;
  error?: string;
}> {
  if (!bookId || typeof bookId !== 'string' || !bookId.trim()) {
    return { success: false, error: 'bookId is required' };
  }

  const validTypes: NoteType[] = ['personal_note', 'key_takeaway', 'question'];
  if (!validTypes.includes(noteType)) {
    return { success: false, error: `Invalid noteType. Expected one of: ${validTypes.join(', ')}` };
  }

  if (!content || typeof content !== 'string' || !content.trim()) {
    return { success: false, error: 'content cannot be empty' };
  }

  if (content.trim().length > 5000) {
    return { success: false, error: 'content exceeds maximum length of 5000 characters' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized: Please sign in to create notes' };
    }

    const { note, recallItem } = await ApiService.createNoteWithRecall(bookId.trim(), noteType, content.trim());
    safeRevalidatePath(`/book/${encodeURIComponent(bookId.trim())}`);
    safeRevalidatePath('/favorites');

    return {
      success: true,
      note,
      recallItem,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to create note';
    return {
      success: false,
      error: msg,
    };
  }
}

/**
 * Updates an existing note owned by the authenticated user.
 */
export async function updateNote(
  noteId: string,
  content: string,
  noteType?: NoteType
): Promise<{
  success: boolean;
  note?: LearningNote;
  error?: string;
}> {
  if (!noteId || typeof noteId !== 'string' || !noteId.trim()) {
    return { success: false, error: 'noteId is required' };
  }

  if (!content || typeof content !== 'string' || !content.trim()) {
    return { success: false, error: 'content cannot be empty' };
  }

  if (content.trim().length > 5000) {
    return { success: false, error: 'content exceeds maximum length of 5000 characters' };
  }

  if (noteType) {
    const validTypes: NoteType[] = ['personal_note', 'key_takeaway', 'question'];
    if (!validTypes.includes(noteType)) {
      return { success: false, error: `Invalid noteType. Expected one of: ${validTypes.join(', ')}` };
    }
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized: Please sign in to update notes' };
    }

    const note = await ApiService.updateNote(noteId.trim(), content.trim(), noteType);
    if (note.bookId) {
      safeRevalidatePath(`/book/${encodeURIComponent(note.bookId)}`);
    }
    safeRevalidatePath('/favorites');

    return {
      success: true,
      note,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to update note';
    return {
      success: false,
      error: msg,
    };
  }
}

/**
 * Deletes a note owned by the authenticated user.
 */
export async function deleteNote(
  noteId: string,
  bookId?: string
): Promise<{
  success: boolean;
  error?: string;
}> {
  if (!noteId || typeof noteId !== 'string' || !noteId.trim()) {
    return { success: false, error: 'noteId is required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized: Please sign in to delete notes' };
    }

    const ok = await ApiService.deleteNote(noteId.trim());
    if (bookId) {
      safeRevalidatePath(`/book/${encodeURIComponent(bookId.trim())}`);
    }
    safeRevalidatePath('/favorites');

    return {
      success: ok,
      error: ok ? undefined : 'Failed to delete note',
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to delete note';
    return {
      success: false,
      error: msg,
    };
  }
}

/**
 * Retrieves all notes for the authenticated user, with optional filters and keyword search.
 */
export async function getAllUserNotes(params: {
  bookId?: string;
  noteType?: NoteType;
  query?: string;
  limit?: number;
  offset?: number;
} = {}): Promise<{
  success: boolean;
  notes: LearningNote[];
  total: number;
  error?: string;
}> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, notes: [], total: 0, error: 'Unauthorized: Please sign in' };
    }

    const result = await ApiService.getNotes(params);
    return {
      success: true,
      notes: result.notes,
      total: result.total,
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to retrieve notes';
    return {
      success: false,
      notes: [],
      total: 0,
      error: msg,
    };
  }
}

/**
 * Retrieves notes due for smart review / spaced repetition.
 */
export async function getDueReviewsAction(limit: number = 50): Promise<{
  success: boolean;
  reviews: NoteReview[];
  error?: string;
}> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, reviews: [], error: 'Unauthorized' };
    }

    const reviews = await ApiService.getDueReviews(limit);
    return { success: true, reviews };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to fetch due reviews';
    return { success: false, reviews: [], error: msg };
  }
}

/**
 * Retrieves aggregate smart review statistics.
 */
export async function getReviewStatsAction(): Promise<{
  success: boolean;
  stats?: { total: number; due: number; upcoming: number; completed: number };
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

    const stats = await ApiService.getReviewStats();
    return { success: true, stats };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to fetch review stats';
    return { success: false, error: msg };
  }
}

/**
 * Submits outcome of reviewing a note ('remembered' | 'struggled').
 */
export async function submitReviewAction(
  noteId: string,
  outcome: 'remembered' | 'struggled'
): Promise<{
  success: boolean;
  review?: NoteReview;
  error?: string;
}> {
  if (!noteId || !outcome) {
    return { success: false, error: 'noteId and outcome are required' };
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

    const review = await ApiService.submitReview(noteId.trim(), outcome);
    safeRevalidatePath('/discovery');
    safeRevalidatePath('/favorites');
    return { success: true, review };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to submit review';
    return { success: false, error: msg };
  }
}

/**
 * Exports user notes as Markdown.
 */
export async function exportNotesAction(bookId?: string): Promise<{
  success: boolean;
  filename?: string;
  content?: string;
  mime_type?: string;
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

    const result = await ApiService.exportNotes(bookId?.trim());
    return { success: true, ...result };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to export notes';
    return { success: false, error: msg };
  }
}

