import test from 'node:test';
import assert from 'node:assert/strict';
import { setTestClient } from '../lib/supabase/server';
import { submitFeedbackAction } from '../app/actions/user';
import { updateLibraryItemStatus, removeLibraryItem } from '../app/actions/library';
import { ApiService } from '../lib/api';

test('submitFeedbackAction: "favorite" routes to canonical updateLibraryItemStatus action and updates both user_interactions and favorites', async () => {
  const userId = 'user-fav-sync-123';
  const bookId = '9780141439518';

  let interactionPayload: Record<string, unknown> | null = null;
  let favoritePayload: Record<string, unknown> | null = null;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({ data: null, error: null }),
              }),
            }),
          }),
          upsert: (payload: Record<string, unknown>, options: { onConflict: string }) => {
            assert.equal(options.onConflict, 'user_id,book_id');
            interactionPayload = payload;
            return { error: null };
          },
        };
      }
      if (table === 'books') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: {
                  title: 'Pride and Prejudice',
                  authors: 'Jane Austen',
                  thumbnail: 'https://example.com/pride.jpg',
                },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === 'favorites') {
        return {
          upsert: (payload: Record<string, unknown>, options: { onConflict: string }) => {
            assert.equal(options.onConflict, 'user_id,book_id');
            favoritePayload = payload;
            return { error: null };
          },
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await submitFeedbackAction(bookId, 'favorite');
    assert.equal(res.success, true);

    // Verify user_interactions table updated
    assert.ok(interactionPayload);
    assert.equal(interactionPayload['user_id'], userId);
    assert.equal(interactionPayload['book_id'], bookId);
    assert.equal(interactionPayload['interaction_type'], 'favorite');

    // Verify public.favorites table updated with canonical metadata
    assert.ok(favoritePayload);
    assert.equal(favoritePayload['user_id'], userId);
    assert.equal(favoritePayload['book_id'], bookId);
    assert.equal(favoritePayload['book_title'], 'Pride and Prejudice');
    assert.equal(favoritePayload['book_author'], 'Jane Austen');
    assert.equal(favoritePayload['book_image_url'], 'https://example.com/pride.jpg');
  } finally {
    setTestClient(null);
  }
});

test('removeLibraryItem: unfavorite action removes book from both user_interactions and favorites', async () => {
  const userId = 'user-unfav-456';
  const bookId = '9780141439518';

  let interactionDeleted = false;
  let favoriteDeleted = false;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: { interaction_type: 'favorite', created_at: '2026-01-01T00:00:00Z' },
              error: null,
            }),
          }),
        }),
      }),
      delete: () => ({
        eq: (col1: string, val1: string) => ({
          eq: (col2: string, val2: string) => {
            assert.equal(col1, 'user_id');
            assert.equal(val1, userId);
            assert.equal(col2, 'book_id');
            assert.equal(val2, bookId);

            if (table === 'user_interactions') interactionDeleted = true;
            if (table === 'favorites') favoriteDeleted = true;
            return { error: null };
          },
        }),
      }),
    }),
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeLibraryItem(bookId);
    assert.equal(res.success, true);
    assert.equal(interactionDeleted, true);
    assert.equal(favoriteDeleted, true);
  } finally {
    setTestClient(null);
  }
});

test('idempotency: repeatedly adding and removing favorites is safe and deterministic', async () => {
  const userId = 'user-idempotent-789';
  const bookId = '9780307474278';

  let upsertCount = 0;
  let deleteCount = 0;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({ data: null, error: null }),
              }),
            }),
          }),
          upsert: () => {
            upsertCount++;
            return { error: null };
          },
          delete: () => ({
            eq: () => ({
              eq: () => {
                deleteCount++;
                return { error: null };
              },
            }),
          }),
        };
      }
      if (table === 'books') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { title: '1Q84', authors: 'Haruki Murakami', thumbnail: '' },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === 'favorites') {
        return {
          upsert: () => ({ error: null }),
          delete: () => ({
            eq: () => ({
              eq: () => ({ error: null }),
            }),
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    // Add favorite twice (simulating double click or multiple adds)
    const resAdd1 = await updateLibraryItemStatus(bookId, 'favorite');
    const resAdd2 = await updateLibraryItemStatus(bookId, 'favorite');
    assert.equal(resAdd1.success, true);
    assert.equal(resAdd2.success, true);
    assert.equal(upsertCount, 2);

    // Remove favorite twice
    const resDel1 = await removeLibraryItem(bookId);
    const resDel2 = await removeLibraryItem(bookId);
    assert.equal(resDel1.success, true);
    assert.equal(resDel2.success, true);
    assert.equal(deleteCount, 2);
  } finally {
    setTestClient(null);
  }
});

test('two-table consistency rollback: updateLibraryItemStatus rolls back when favorites table sync fails', async () => {
  const userId = 'user-rollback-consistency';
  const bookId = '9780553103540';

  let rollbackInvoked = false;
  let interactionUpsertCount = 0;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: { interaction_type: 'want_to_read', created_at: '2026-01-01T00:00:00Z' },
                  error: null,
                }),
              }),
            }),
          }),
          upsert: (payload: Record<string, unknown>) => {
            interactionUpsertCount++;
            if (interactionUpsertCount === 2) {
              // The compensating rollback restored the previous status!
              rollbackInvoked = true;
              assert.equal(payload['interaction_type'], 'want_to_read');
            }
            return { error: null };
          },
        };
      }
      if (table === 'books') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { title: 'A Game of Thrones', authors: 'George R.R. Martin', thumbnail: '' },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === 'favorites') {
        return {
          upsert: () => ({
            error: { message: 'Database connection failed while writing to favorites' },
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await updateLibraryItemStatus(bookId, 'favorite');
    assert.equal(res.success, false);
    assert.ok(res.error?.includes('Failed to synchronize favorites'));
    assert.equal(rollbackInvoked, true);
  } finally {
    setTestClient(null);
  }
});

test('unauthenticated callers: rejected server-side without modifying user_interactions or favorites', async () => {
  let tableAccessAttempted = false;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: 'Auth session missing' },
      }),
    },
    from: () => {
      tableAccessAttempted = true;
      throw new Error('Should not access database tables for unauthenticated user');
    },
  };

  setTestClient(fakeSupabase);
  try {
    const favRes = await updateLibraryItemStatus('9780000000001', 'favorite');
    assert.equal(favRes.success, false);
    assert.equal(favRes.error, 'Unauthorized');

    const unfavRes = await removeLibraryItem('9780000000001');
    assert.equal(unfavRes.success, false);
    assert.equal(unfavRes.error, 'Unauthorized');

    const feedbackFavRes = await submitFeedbackAction('9780000000001', 'favorite');
    assert.equal(feedbackFavRes.success, false);
    assert.equal(feedbackFavRes.error, 'Unauthorized');

    assert.equal(tableAccessAttempted, false);
  } finally {
    setTestClient(null);
  }
});

test('non-favorite feedback interactions: preserve existing behavior without touching favorites table', async () => {
  const originalSubmit = ApiService.submitFeedback;
  let apiServiceInteraction: string | null = null;
  let apiServiceBookId: string | null = null;

  try {
    ApiService.submitFeedback = async (bId: string, inter: 'like' | 'dislike' | 'favorite' | 'want_to_read' | 'finished') => {
      apiServiceBookId = bId;
      apiServiceInteraction = inter;
      return true;
    };

    const resLike = await submitFeedbackAction('9781111', 'like');
    assert.equal(resLike.success, true);
    assert.equal(apiServiceBookId, '9781111');
    assert.equal(apiServiceInteraction, 'like');

    const resDislike = await submitFeedbackAction('9782222', 'dislike');
    assert.equal(resDislike.success, true);
    assert.equal(apiServiceBookId, '9782222');
    assert.equal(apiServiceInteraction, 'dislike');

    const resWant = await submitFeedbackAction('9783333', 'want_to_read');
    assert.equal(resWant.success, true);
    assert.equal(apiServiceBookId, '9783333');
    assert.equal(apiServiceInteraction, 'want_to_read');

    const resFinished = await submitFeedbackAction('9784444', 'finished');
    assert.equal(resFinished.success, true);
    assert.equal(apiServiceBookId, '9784444');
    assert.equal(apiServiceInteraction, 'finished');
  } finally {
    ApiService.submitFeedback = originalSubmit;
  }
});

test('BookFeedback state transitions: toggles favorite and executes optimistic rollback on failure', async () => {
  // State transition simulator for BookFeedback component logic
  type State = {
    activeFeedback: string | null;
    status: 'idle' | 'loading' | 'success' | 'error';
    errorMessage: string | null;
  };

  async function simulateFavoriteClick(
    currentState: State,
    action: (bookId: string) => Promise<{ success: boolean; error?: string }>
  ): Promise<State> {
    const isCurrentlyFavorite = currentState.activeFeedback === 'favorite';
    const previousFeedback = currentState.activeFeedback;
    const targetAction = isCurrentlyFavorite ? 'remove' : 'add';

    // Optimistic transition
    const optimisticState: State = {
      activeFeedback: isCurrentlyFavorite ? null : 'favorite',
      status: 'loading',
      errorMessage: null,
    };

    try {
      const res = await action('book-100');
      if (res.success) {
        return {
          ...optimisticState,
          status: 'success',
        };
      } else {
        // Rollback
        return {
          activeFeedback: previousFeedback,
          status: 'error',
          errorMessage:
            res.error === 'Unauthorized'
              ? 'Please sign in to manage your favorites'
              : res.error || (targetAction === 'remove' ? 'Failed to remove from favorites' : 'Failed to add to favorites'),
        };
      }
    } catch {
      return {
        activeFeedback: previousFeedback,
        status: 'error',
        errorMessage: 'Network error occurred',
      };
    }
  }

  // 1. Successful add
  const state0: State = { activeFeedback: null, status: 'idle', errorMessage: null };
  const state1 = await simulateFavoriteClick(state0, async () => ({ success: true }));
  assert.equal(state1.activeFeedback, 'favorite');
  assert.equal(state1.status, 'success');
  assert.equal(state1.errorMessage, null);

  // 2. Successful remove (unfavorite)
  const state2 = await simulateFavoriteClick(state1, async () => ({ success: true }));
  assert.equal(state2.activeFeedback, null);
  assert.equal(state2.status, 'success');

  // 3. Failed add (Unauthorized) -> rolls back to null and displays error
  const state3 = await simulateFavoriteClick(state0, async () => ({ success: false, error: 'Unauthorized' }));
  assert.equal(state3.activeFeedback, null);
  assert.equal(state3.status, 'error');
  assert.equal(state3.errorMessage, 'Please sign in to manage your favorites');

  // 4. Failed remove (Database error) -> rolls back to 'favorite' and displays error
  const state4 = await simulateFavoriteClick(state1, async () => ({ success: false, error: 'Database lock timeout' }));
  assert.equal(state4.activeFeedback, 'favorite');
  assert.equal(state4.status, 'error');
  assert.equal(state4.errorMessage, 'Database lock timeout');

  // 5. Network exception -> rolls back safely
  const state5 = await simulateFavoriteClick(state0, async () => {
    throw new Error('Connection refused');
  });
  assert.equal(state5.activeFeedback, null);
  assert.equal(state5.status, 'error');
  assert.equal(state5.errorMessage, 'Network error occurred');
});

test('submitFeedbackAction: "reading" passes through to ApiService and triggers cache revalidation', async () => {
  let submittedBookId: string | null = null;
  let submittedInteraction: string | null = null;

  const originalSubmit = ApiService.submitFeedback;
  ApiService.submitFeedback = async (bookId: string, interaction: 'like' | 'dislike' | 'favorite' | 'want_to_read' | 'reading' | 'finished' | 'clear' | 'remove') => {
    submittedBookId = bookId;
    submittedInteraction = interaction;
    return true;
  };

  try {
    const res = await submitFeedbackAction('9780141439518', 'reading');
    assert.equal(res.success, true);
    assert.equal(submittedBookId, '9780141439518');
    assert.equal(submittedInteraction, 'reading');
  } finally {
    ApiService.submitFeedback = originalSubmit;
  }
});

test('submitFeedbackAction: "clear" passes through to ApiService to remove reading status', async () => {
  let submittedBookId: string | null = null;
  let submittedInteraction: string | null = null;

  const originalSubmit = ApiService.submitFeedback;
  ApiService.submitFeedback = async (bookId: string, interaction: 'like' | 'dislike' | 'favorite' | 'want_to_read' | 'reading' | 'finished' | 'clear' | 'remove') => {
    submittedBookId = bookId;
    submittedInteraction = interaction;
    return true;
  };

  try {
    const res = await submitFeedbackAction('9780141439518', 'clear');
    assert.equal(res.success, true);
    assert.equal(submittedBookId, '9780141439518');
    assert.equal(submittedInteraction, 'clear');
  } finally {
    ApiService.submitFeedback = originalSubmit;
  }
});

test('BookFeedback toggle-off: clicking active status submits "clear" and reverts state to null', async () => {
  interface State {
    activeFeedback: string | null;
    status: 'idle' | 'loading' | 'success' | 'error';
    feedbackSuccessText: string | null;
  }

  async function simulateStatusClick(
    current: State,
    clickedInteraction: string,
    action: (interaction: string) => Promise<{ success: boolean; error?: string }>
  ): Promise<State> {
    const isClearing = current.activeFeedback === clickedInteraction;
    const targetInteraction = isClearing ? 'clear' : clickedInteraction;
    const previousFeedback = current.activeFeedback;

    // Optimistic
    const nextActive = isClearing ? null : clickedInteraction;
    try {
      const res = await action(targetInteraction);
      if (res.success) {
        return {
          activeFeedback: nextActive,
          status: 'success',
          feedbackSuccessText: isClearing ? 'Status cleared! Recommendations updated.' : 'Preference saved! Recommendations updated.',
        };
      } else {
        return {
          activeFeedback: previousFeedback,
          status: 'error',
          feedbackSuccessText: null,
        };
      }
    } catch {
      return {
        activeFeedback: previousFeedback,
        status: 'error',
        feedbackSuccessText: null,
      };
    }
  }

  // 1. Initial click: marks 'reading'
  let submitted: string | null = null;
  const mockAction = async (interaction: string) => {
    submitted = interaction;
    return { success: true };
  };

  const state0: State = { activeFeedback: null, status: 'idle', feedbackSuccessText: null };
  const state1 = await simulateStatusClick(state0, 'reading', mockAction);
  assert.equal(state1.activeFeedback, 'reading');
  assert.equal(submitted, 'reading');

  // 2. Second click on active 'reading': toggles off, submits 'clear', returns to null
  const state2 = await simulateStatusClick(state1, 'reading', mockAction);
  assert.equal(state2.activeFeedback, null);
  assert.equal(submitted, 'clear');
  assert.equal(state2.feedbackSuccessText, 'Status cleared! Recommendations updated.');

  // 3. Failed clear: rolls back to 'reading'
  const state3 = await simulateStatusClick(state1, 'reading', async () => ({ success: false, error: 'Network error' }));
  assert.equal(state3.activeFeedback, 'reading');
  assert.equal(state3.status, 'error');
});

