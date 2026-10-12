import test from 'node:test';
import assert from 'node:assert/strict';
import { setTestClient } from '../lib/supabase/server';
import {
  getLibraryBooks,
  removeLibraryItem,
  updateLibraryItemStatus,
} from '../app/actions/library';
import type { LibraryCollectionStatus } from '../types';

test('getLibraryBooks: rejects unauthenticated callers with Unauthorized', async () => {
  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: 'JWT expired' },
      }),
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await getLibraryBooks();
    assert.equal(res.success, false);
    assert.ok(res.error?.includes('Unauthorized'));
    assert.deepEqual(res.items, []);
  } finally {
    setTestClient(null);
  }
});

test('getLibraryBooks: loads, deduplicates, and normalizes library collections for authenticated user', async () => {
  const userId = 'user-test-uuid-456';

  const mockInteractions = [
    { book_id: '9780001', interaction_type: 'favorite', created_at: '2026-02-01T12:00:00Z' },
    { book_id: '9780002', interaction_type: 'want_to_read', created_at: '2026-02-02T12:00:00Z' },
    { book_id: '9780003', interaction_type: 'finished', created_at: '2026-02-03T12:00:00Z' },
  ];

  const mockMobileFavorites = [
    // Duplicate of 9780001 from mobile sync
    {
      book_id: '9780001',
      book_title: 'Duplicated Book',
      book_author: 'Author A',
      book_image_url: 'https://example.com/a.jpg',
      added_at: '2026-02-01T12:00:00Z',
    },
    // Unique mobile favorite
    {
      book_id: '9780004',
      book_title: 'Mobile Only Book',
      book_author: 'Author M',
      book_image_url: 'https://example.com/m.jpg',
      added_at: '2026-02-04T12:00:00Z',
    },
  ];

  const mockBooks = [
    {
      isbn13: '9780001',
      title: 'The Great Journey',
      authors: 'Author One',
      average_rating: 4.5,
      ratings_count: 100,
      thumbnail: 'https://example.com/1.jpg',
    },
    {
      isbn13: '9780002',
      title: 'Future Horizons',
      authors: 'Author Two',
      average_rating: 4.8,
      ratings_count: 250,
      thumbnail: 'https://example.com/2.jpg',
    },
    {
      isbn13: '9780003',
      title: 'Historical Chronicles',
      authors: 'Author Three',
      average_rating: 4.0,
      ratings_count: 50,
      thumbnail: 'https://example.com/3.jpg',
    },
  ];

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId, email: 'reader@example.com' } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'user_interactions') {
        return {
          select: () => ({
            eq: (col: string, val: string) => {
              assert.equal(col, 'user_id');
              assert.equal(val, userId);
              return {
                in: (typeCol: string, types: string[]) => {
                  assert.equal(typeCol, 'interaction_type');
                  assert.ok(Array.isArray(types));
                  return {
                    order: () => ({
                      data: mockInteractions,
                      error: null,
                    }),
                  };
                },
              };
            },
          }),
        };
      }

      if (table === 'favorites') {
        return {
          select: () => ({
            eq: (col: string, val: string) => {
              assert.equal(col, 'user_id');
              assert.equal(val, userId);
              return {
                data: mockMobileFavorites,
                error: null,
              };
            },
          }),
        };
      }

      if (table === 'books') {
        return {
          select: () => ({
            in: (col: string, ids: string[]) => {
              assert.equal(col, 'isbn13');
              assert.ok(Array.isArray(ids));
              return {
                data: mockBooks,
                error: null,
              };
            },
          }),
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await getLibraryBooks();
    assert.equal(res.success, true);
    assert.equal(res.items.length, 4); // 9780001, 9780002, 9780003, 9780004 (no duplicate!)

    const item1 = res.items.find((i) => i.bookId === '9780001');
    assert.ok(item1);
    assert.equal(item1.status, 'favorite');
    assert.equal(item1.book.title, 'The Great Journey');

    const item2 = res.items.find((i) => i.bookId === '9780002');
    assert.ok(item2);
    assert.equal(item2.status, 'want_to_read');
    assert.equal(item2.book.title, 'Future Horizons');

    const item3 = res.items.find((i) => i.bookId === '9780003');
    assert.ok(item3);
    assert.equal(item3.status, 'finished');
    assert.equal(item3.book.title, 'Historical Chronicles');

    const item4 = res.items.find((i) => i.bookId === '9780004');
    assert.ok(item4);
    assert.equal(item4.status, 'favorite');
    assert.equal(item4.book.title, 'Mobile Only Book');
  } finally {
    setTestClient(null);
  }
});

test('removeLibraryItem: deletes from user_interactions and favorites scoped to user_id', async () => {
  const userId = 'user-delete-test';
  let deletedFromInteractions = false;
  let deletedFromFavorites = false;

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
            assert.equal(val2, '9789999');

            if (table === 'user_interactions') deletedFromInteractions = true;
            if (table === 'favorites') deletedFromFavorites = true;
            return { error: null };
          },
        }),
      }),
    }),
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeLibraryItem('9789999');
    assert.equal(res.success, true);
    assert.equal(deletedFromInteractions, true);
    assert.equal(deletedFromFavorites, true);
  } finally {
    setTestClient(null);
  }
});

test('removeLibraryItem: executes compensating rollback when favorites deletion fails', async () => {
  const userId = 'user-rollback-test';
  let restored = false;

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
          delete: () => ({
            eq: () => ({
              eq: () => ({ error: null }),
            }),
          }),
          insert: (payload: Record<string, unknown>) => {
            assert.equal(payload['user_id'], userId);
            assert.equal(payload['interaction_type'], 'want_to_read');
            restored = true;
            return { error: null };
          },
        };
      }
      if (table === 'favorites') {
        return {
          delete: () => ({
            eq: () => ({
              eq: () => ({ error: { message: 'Database lock timeout' } }),
            }),
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeLibraryItem('9781234');
    assert.equal(res.success, false);
    assert.ok(res.error?.includes('Failed to remove from favorites table'));
    assert.equal(restored, true); // Compensating rollback verified!
  } finally {
    setTestClient(null);
  }
});

test('removeLibraryItem: rejects unauthenticated callers', async () => {
  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: 'Unauthorized' },
      }),
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await removeLibraryItem('9789999');
    assert.equal(res.success, false);
    assert.equal(res.error, 'Unauthorized');
  } finally {
    setTestClient(null);
  }
});

test('updateLibraryItemStatus: validates statuses and updates collections', async () => {
  const userId = 'user-status-test';
  let upsertedInteraction: Record<string, unknown> | null = null;
  let favoritesDeleted = false;

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
                  data: { interaction_type: 'favorite', created_at: '2026-01-01T00:00:00Z' },
                  error: null,
                }),
              }),
            }),
          }),
          upsert: (payload: Record<string, unknown>, options: { onConflict: string }) => {
            upsertedInteraction = payload;
            assert.equal(options.onConflict, 'user_id,book_id');
            return { error: null };
          },
        };
      }
      if (table === 'favorites') {
        return {
          delete: () => ({
            eq: () => ({
              eq: () => {
                favoritesDeleted = true;
                return { error: null };
              },
            }),
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    // Valid transition to want_to_read
    const res = await updateLibraryItemStatus('9785555', 'want_to_read');
    assert.equal(res.success, true);
    assert.ok(upsertedInteraction);
    assert.equal(upsertedInteraction['user_id'], userId);
    assert.equal(upsertedInteraction['book_id'], '9785555');
    assert.equal(upsertedInteraction['interaction_type'], 'want_to_read');
    assert.equal(favoritesDeleted, true);

    // Invalid status validation
    const invalidRes = await updateLibraryItemStatus('9785555', 'invalid_status' as unknown as LibraryCollectionStatus);
    assert.equal(invalidRes.success, false);
    assert.ok(invalidRes.error?.includes('Invalid collection status'));
  } finally {
    setTestClient(null);
  }
});

test('updateLibraryItemStatus: executes compensating rollback when favorites sync fails', async () => {
  const userId = 'user-sync-fail-test';
  let rolledBackInteraction: Record<string, unknown> | null = null;
  let firstUpsertDone = false;

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
            if (!firstUpsertDone) {
              firstUpsertDone = true;
              return { error: null };
            }
            // Second upsert is the compensating rollback!
            rolledBackInteraction = payload;
            return { error: null };
          },
        };
      }
      if (table === 'books') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { title: 'Test Book', authors: 'Author', thumbnail: '' },
                error: null,
              }),
            }),
          }),
        };
      }
      if (table === 'favorites') {
        return {
          upsert: () => ({
            error: { message: 'Favorites disk quota exceeded' },
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await updateLibraryItemStatus('9787777', 'favorite');
    assert.equal(res.success, false);
    assert.ok(res.error?.includes('Failed to synchronize favorites'));
    assert.ok(rolledBackInteraction);
    assert.equal(rolledBackInteraction['interaction_type'], 'want_to_read'); // Rolled back!
  } finally {
    setTestClient(null);
  }
});

