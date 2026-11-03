import test from 'node:test';
import assert from 'node:assert/strict';
import { setTestClient } from '../lib/supabase/server';
import {
  removeFavoriteItem,
  addFavoriteItem,
  removeLibraryItem,
  getBookInteraction,
} from '../app/actions/library';

// ── 1. Saf Favori Kaldırma (Pure Favorite Removal) ────────────────────────────

test('regression: pure favorite is removed and no favorite record remains in either table', async () => {
  const userId = 'user-pure-fav-001';
  const bookId = '9780141439518';

  let favoriteDeleted = false;
  let interactionDeleted = false;
  let interactionDeleteTypeFilter: string | null = null;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'favorites') {
        return {
          select: () => ({
            eq: (col1: string, val1: string) => ({
              eq: (col2: string, val2: string) => {
                assert.equal(col1, 'user_id');
                assert.equal(val1, userId);
                assert.equal(col2, 'book_id');
                assert.equal(val2, bookId);
                return {
                  maybeSingle: async () => ({
                    data: {
                      book_id: bookId,
                      book_title: 'Pride and Prejudice',
                      book_author: 'Jane Austen',
                      book_image_url: 'https://example.com/pride.jpg',
                      added_at: '2026-01-01T10:00:00Z',
                    },
                    error: null,
                  }),
                };
              },
            }),
          }),
          delete: () => ({
            eq: (col1: string, val1: string) => ({
              eq: (col2: string, val2: string) => {
                assert.equal(col1, 'user_id');
                assert.equal(val1, userId);
                assert.equal(col2, 'book_id');
                assert.equal(val2, bookId);
                favoriteDeleted = true;
                return { error: null };
              },
            }),
          }),
        };
      }

      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: (col1: string, val1: string) => ({
              eq: (col2: string, val2: string) => {
                assert.equal(col1, 'user_id');
                assert.equal(val1, userId);
                assert.equal(col2, 'book_id');
                assert.equal(val2, bookId);
                return {
                  maybeSingle: async () => ({
                    data: { interaction_type: 'favorite', created_at: '2026-01-01T10:00:00Z' },
                    error: null,
                  }),
                };
              },
            }),
          }),
          delete: () => ({
            eq: (col1: string, val1: string) => ({
              eq: (col2: string, val2: string) => ({
                eq: (col3: string, val3: string) => {
                  assert.equal(col1, 'user_id');
                  assert.equal(val1, userId);
                  assert.equal(col2, 'book_id');
                  assert.equal(val2, bookId);
                  assert.equal(col3, 'interaction_type');
                  interactionDeleteTypeFilter = val3;
                  interactionDeleted = true;
                  return { error: null };
                },
              }),
            }),
          }),
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeFavoriteItem(bookId);
    assert.equal(res.success, true);
    assert.equal(favoriteDeleted, true, 'favorites table entry must be deleted');
    assert.equal(interactionDeleted, true, 'user_interactions pure favorite entry must be deleted');
    assert.equal(interactionDeleteTypeFilter, 'favorite', 'must strictly filter by interaction_type = favorite');
  } finally {
    setTestClient(null);
  }
});

// ── 2. reading + Favori Durumu (Preserve reading) ─────────────────────────────

test('regression: removing favorite when book is "reading" removes favorite but preserves "reading" status', async () => {
  const userId = 'user-reading-fav-002';
  const bookId = '9780441172719'; // Dune

  let favoriteDeleted = false;
  let interactionDeleteAttempted = false;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'favorites') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: { book_id: bookId, book_title: 'Dune', added_at: '2026-01-01T00:00:00Z' },
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
                favoriteDeleted = true;
                return { error: null };
              },
            }),
          }),
        };
      }

      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: (col1: string, val1: string) => ({
              eq: (col2: string, val2: string) => {
                assert.equal(col1, 'user_id');
                assert.equal(val1, userId);
                assert.equal(col2, 'book_id');
                assert.equal(val2, bookId);
                return {
                  maybeSingle: async () => ({
                    data: { interaction_type: 'reading', created_at: '2026-01-02T12:00:00Z' },
                    error: null,
                  }),
                };
              },
            }),
          }),
          delete: () => {
            interactionDeleteAttempted = true;
            throw new Error('CRITICAL BUG: user_interactions should NEVER be deleted when status is reading!');
          },
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeFavoriteItem(bookId);
    assert.equal(res.success, true);
    assert.equal(favoriteDeleted, true, 'favorites record must be removed');
    assert.equal(interactionDeleteAttempted, false, 'reading interaction must NEVER be deleted');
  } finally {
    setTestClient(null);
  }
});

// ── 3. finished + Favori Durumu (Preserve finished) ────────────────────────────

test('regression: removing favorite when book is "finished" removes favorite but preserves "finished" status', async () => {
  const userId = 'user-finished-fav-003';
  const bookId = '9780061120084'; // To Kill a Mockingbird

  let favoriteDeleted = false;
  let interactionDeleteAttempted = false;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'favorites') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: { book_id: bookId, book_title: 'To Kill a Mockingbird' },
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
                favoriteDeleted = true;
                return { error: null };
              },
            }),
          }),
        };
      }

      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: (col1: string, val1: string) => ({
              eq: (col2: string, val2: string) => {
                assert.equal(col1, 'user_id');
                assert.equal(val1, userId);
                assert.equal(col2, 'book_id');
                assert.equal(val2, bookId);
                return {
                  maybeSingle: async () => ({
                    data: { interaction_type: 'finished', created_at: '2026-01-03T18:00:00Z' },
                    error: null,
                  }),
                };
              },
            }),
          }),
          delete: () => {
            interactionDeleteAttempted = true;
            throw new Error('CRITICAL BUG: user_interactions should NEVER be deleted when status is finished!');
          },
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeFavoriteItem(bookId);
    assert.equal(res.success, true);
    assert.equal(favoriteDeleted, true);
    assert.equal(interactionDeleteAttempted, false, 'finished interaction must be strictly preserved');
  } finally {
    setTestClient(null);
  }
});

// ── 4. like, dislike ve want_to_read Sinyallerinin Korunması ─────────────────

test('regression: removing favorite does not delete "like", "dislike", or "want_to_read" signals', async () => {
  const userId = 'user-signals-004';

  for (const signal of ['like', 'dislike', 'want_to_read'] as const) {
    const bookId = `978000000000${signal.length}`;
    let favoriteDeleted = false;
    let interactionDeleteAttempted = false;

    const fakeSupabase = {
      auth: {
        getUser: async () => ({
          data: { user: { id: userId } },
          error: null,
        }),
      },
      from: (table: string) => {
        if (table === 'favorites') {
          return {
            select: () => ({
              eq: () => ({
                eq: () => ({
                  maybeSingle: async () => ({
                    data: { book_id: bookId, book_title: `Signal Book ${signal}` },
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
                  favoriteDeleted = true;
                  return { error: null };
                },
              }),
            }),
          };
        }

        if (table === 'user_interactions') {
          return {
            select: () => ({
              eq: () => ({
                eq: () => ({
                  maybeSingle: async () => ({
                    data: { interaction_type: signal, created_at: '2026-01-04T00:00:00Z' },
                    error: null,
                  }),
                }),
              }),
            }),
            delete: () => {
              interactionDeleteAttempted = true;
              throw new Error(`CRITICAL BUG: signal "${signal}" must not be deleted upon unfavorite!`);
            },
          };
        }

        throw new Error(`Unexpected table: ${table}`);
      },
    };

    setTestClient(fakeSupabase);
    try {
      const res = await removeFavoriteItem(bookId);
      assert.equal(res.success, true);
      assert.equal(favoriteDeleted, true);
      assert.equal(interactionDeleteAttempted, false, `signal "${signal}" must NOT be deleted`);
    } finally {
      setTestClient(null);
    }
  }
});

// ── 5. Kütüphaneden Tamamen Kaldırma (removeLibraryItem) Sözleşmesi ────────────

test('regression: removeLibraryItem completely deletes both user_interactions and favorites', async () => {
  const userId = 'user-complete-remove-005';
  const bookId = '9780547928227'; // The Hobbit

  let interactionDeleted = false;
  let favoriteDeleted = false;

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
                  data: { interaction_type: 'reading', created_at: '2026-01-05T00:00:00Z' },
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
                interactionDeleted = true;
                return { error: null };
              },
            }),
          }),
        };
      }

      if (table === 'favorites') {
        return {
          delete: () => ({
            eq: (col1: string, val1: string) => ({
              eq: (col2: string, val2: string) => {
                assert.equal(col1, 'user_id');
                assert.equal(val1, userId);
                assert.equal(col2, 'book_id');
                assert.equal(val2, bookId);
                favoriteDeleted = true;
                return { error: null };
              },
            }),
          }),
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeLibraryItem(bookId);
    assert.equal(res.success, true);
    assert.equal(interactionDeleted, true, 'complete removal MUST delete from user_interactions');
    assert.equal(favoriteDeleted, true, 'complete removal MUST delete from favorites');
  } finally {
    setTestClient(null);
  }
});

// ── 6. Compensating Rollback ve Optimistic İstemci Durumunun Geri Alınması ────

test('regression: server-side compensating rollback restores favorites if user_interactions delete fails in removeFavoriteItem', async () => {
  const userId = 'user-rollback-srv-006';
  const bookId = '9780345391803'; // The Hitchhiker's Guide

  let favoritesReinserted = false;
  let reinsertedPayload: Record<string, unknown> | null = null;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'favorites') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: {
                    book_id: bookId,
                    book_title: "The Hitchhiker's Guide",
                    book_author: 'Douglas Adams',
                    book_image_url: 'https://example.com/guide.jpg',
                    added_at: '2026-01-06T12:00:00Z',
                  },
                  error: null,
                }),
              }),
            }),
          }),
          delete: () => ({
            eq: () => ({
              eq: () => ({ error: null }),
            }),
          }),
          insert: async (payload: Record<string, unknown>) => {
            favoritesReinserted = true;
            reinsertedPayload = payload;
            return { error: null };
          },
        };
      }

      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  data: { interaction_type: 'favorite', created_at: '2026-01-06T12:00:00Z' },
                  error: null,
                }),
              }),
            }),
          }),
          delete: () => ({
            eq: () => ({
              eq: () => ({
                eq: () => ({
                  error: { message: 'Foreign key lock timeout on user_interactions' },
                }),
              }),
            }),
          }),
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeFavoriteItem(bookId);
    assert.equal(res.success, false);
    assert.ok(res.error?.includes('Failed to remove favorite interaction'));
    assert.equal(favoritesReinserted, true, 'compensating rollback must restore favorites entry');
    assert.equal(reinsertedPayload?.['book_title'], "The Hitchhiker's Guide");
  } finally {
    setTestClient(null);
  }
});

test('regression: client-side optimistic UI rollback restores isFavorite on server failure without corrupting reading state', async () => {
  // Simulator for BookFeedback state management
  type ComponentState = {
    isFavorite: boolean;
    activeFeedback: string | null;
    status: 'idle' | 'loading' | 'success' | 'error';
    errorMessage: string | null;
  };

  async function simulateFavoriteToggle(
    currentState: ComponentState,
    serverCall: () => Promise<{ success: boolean; error?: string }>
  ): Promise<ComponentState> {
    const currentlyFav = currentState.isFavorite;
    const targetAction = currentlyFav ? 'remove' : 'add';

    // Optimistic transition
    const optimistic: ComponentState = {
      ...currentState,
      isFavorite: !currentlyFav,
      status: 'loading',
      errorMessage: null,
    };

    try {
      const res = await serverCall();
      if (res.success) {
        return {
          ...optimistic,
          status: 'success',
        };
      } else {
        // Rollback
        return {
          ...currentState,
          isFavorite: currentlyFav,
          status: 'error',
          errorMessage:
            res.error === 'Unauthorized'
              ? 'Please sign in to manage your favorites'
              : res.error || (targetAction === 'remove' ? 'Failed to remove from favorites' : 'Failed to add to favorites'),
        };
      }
    } catch {
      return {
        ...currentState,
        isFavorite: currentlyFav,
        status: 'error',
        errorMessage: 'Network error occurred',
      };
    }
  }

  // Initial state: user is actively reading AND book is in favorites
  const initialState: ComponentState = {
    isFavorite: true,
    activeFeedback: 'reading',
    status: 'idle',
    errorMessage: null,
  };

  // 1. Successful unfavorite: isFavorite becomes false, but activeFeedback 'reading' is PRESERVED!
  const stateUnfav = await simulateFavoriteToggle(initialState, async () => ({ success: true }));
  assert.equal(stateUnfav.isFavorite, false);
  assert.equal(stateUnfav.activeFeedback, 'reading', 'reading status must remain intact after unfavorite');
  assert.equal(stateUnfav.status, 'success');

  // 2. Failed unfavorite: rolls back isFavorite to true, preserving activeFeedback 'reading'
  const stateFailedUnfav = await simulateFavoriteToggle(initialState, async () => ({
    success: false,
    error: 'PostgreSQL connection dropped',
  }));
  assert.equal(stateFailedUnfav.isFavorite, true, 'isFavorite must rollback to true on failure');
  assert.equal(stateFailedUnfav.activeFeedback, 'reading', 'reading status must remain intact');
  assert.equal(stateFailedUnfav.status, 'error');
  assert.equal(stateFailedUnfav.errorMessage, 'PostgreSQL connection dropped');

  // 3. Network crash rollback: rolls back isFavorite safely
  const stateNetworkError = await simulateFavoriteToggle(initialState, async () => {
    throw new Error('ECONNRESET');
  });
  assert.equal(stateNetworkError.isFavorite, true);
  assert.equal(stateNetworkError.activeFeedback, 'reading');
  assert.equal(stateNetworkError.status, 'error');
  assert.equal(stateNetworkError.errorMessage, 'Network error occurred');
});

// ── 7. Kullanıcı İzolasyonu ve Yetkisiz Erişim Engeli (RLS Scope) ────────────

test('regression: unauthenticated callers are rejected before table queries, and queries are strictly scoped to user.id', async () => {
  let tableAccessAttempted = false;

  const unauthSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: 'Invalid JWT' },
      }),
    },
    from: () => {
      tableAccessAttempted = true;
      throw new Error('Database tables must not be queried for unauthenticated requests');
    },
  };

  setTestClient(unauthSupabase);
  try {
    const resRemove = await removeFavoriteItem('9780000000001');
    assert.equal(resRemove.success, false);
    assert.equal(resRemove.error, 'Unauthorized');

    const resAdd = await addFavoriteItem('9780000000001');
    assert.equal(resAdd.success, false);
    assert.equal(resAdd.error, 'Unauthorized');

    const resInteraction = await getBookInteraction('9780000000001');
    assert.equal(resInteraction.success, true);
    assert.equal(resInteraction.isAuthenticated, false);
    assert.equal(resInteraction.interaction, null);
    assert.equal(resInteraction.isFavorite, false);

    assert.equal(tableAccessAttempted, false, 'No tables accessed for unauthenticated users');
  } finally {
    setTestClient(null);
  }
});

// ── 8. addFavoriteItem Bağımsız Favorileme ve Okuma Durumu Koruması ──────────

test('regression: addFavoriteItem does not overwrite existing reading status in user_interactions', async () => {
  const userId = 'user-add-fav-preserve-008';
  const bookId = '9780140449136'; // The Odyssey

  let favoritesUpserted = false;
  let interactionInsertAttempted = false;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'books') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { title: 'The Odyssey', authors: 'Homer', thumbnail: 'https://example.com/odyssey.jpg' },
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
            assert.equal(payload['user_id'], userId);
            assert.equal(payload['book_id'], bookId);
            assert.equal(payload['book_title'], 'The Odyssey');
            favoritesUpserted = true;
            return { error: null };
          },
        };
      }

      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({
                  // User is already reading this book!
                  data: { interaction_type: 'reading', created_at: '2026-01-08T00:00:00Z' },
                  error: null,
                }),
              }),
            }),
          }),
          insert: () => {
            interactionInsertAttempted = true;
            throw new Error('CRITICAL BUG: user_interactions must NOT be overwritten when reading status already exists!');
          },
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await addFavoriteItem(bookId);
    assert.equal(res.success, true);
    assert.equal(favoritesUpserted, true, 'book must be added to favorites');
    assert.equal(interactionInsertAttempted, false, 'user_interactions must NOT be overwritten');
  } finally {
    setTestClient(null);
  }
});
