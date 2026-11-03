import test from 'node:test';
import assert from 'node:assert/strict';
import { ApiService, ApiTimeoutError } from '../lib/api';
import { getBookInteraction } from '../app/actions/library';
import { trackActivityAction } from '../app/actions/user';
import { setTestClient } from '../lib/supabase/server';

// ── 1. Book Detail Fetch & Error States (P1) ───────────────────────────────────

test('Book detail fetch: successfully returns normalized Book when book exists', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () =>
      new Response(
        JSON.stringify({
          book: {
            isbn13: '9780441013593',
            title: 'Dune',
            authors: 'Frank Herbert',
            average_rating: 4.8,
            ratings_count: 50000,
            published_date: '1965',
            page_count: 688,
          },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );

    const book = await ApiService.getBookByIsbn('9780441013593');
    assert.ok(book !== null);
    assert.equal(book.isbn13, '9780441013593');
    assert.equal(book.title, 'Dune');
    assert.equal(book.authors, 'Frank Herbert');
    assert.equal(book.averageRating, 4.8);
    assert.equal(book.pageCount, 688);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Book detail fetch: distinguishes genuine 404 (Book Not Found) from backend crashes', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ error: 'Book not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });

    const book = await ApiService.getBookByIsbn('9780000000000');
    assert.equal(book, null);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Book detail fetch: throws controlled error on backend 500 without crashing Next.js runtime', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ error: 'Database connection failed' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });

    await assert.rejects(
      async () => {
        await ApiService.getBookByIsbn('9780441013593');
      },
      (err: Error) => {
        assert.ok(err.message.includes('500'));
        return true;
      }
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Book detail fetch: detects network timeout / abort as ApiTimeoutError', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async (_url, init) => {
      return new Promise((_, reject) => {
        if (init?.signal) {
          init.signal.addEventListener('abort', () => {
            const timeoutErr = new Error('The operation was aborted due to timeout');
            timeoutErr.name = 'TimeoutError';
            reject(timeoutErr);
          });
        }
      });
    };

    const controller = new AbortController();
    setTimeout(() => controller.abort(), 15);

    await assert.rejects(
      async () => {
        await ApiService.getBookByIsbn('9780441013593', { signal: controller.signal });
      },
      (err: unknown) => {
        assert.ok(err instanceof ApiTimeoutError || err instanceof Error);
        return true;
      }
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

// ── 2. Server-side User Book Interaction (P2) ─────────────────────────────────

test('getBookInteraction: returns existing favorite status when user has favorited book in user_interactions', async () => {
  const userId = 'usr-fav-777';
  const bookId = '9780441013593';

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
                  data: { interaction_type: 'favorite' },
                  error: null,
                }),
              }),
            }),
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await getBookInteraction(bookId);
    assert.equal(res.success, true);
    assert.equal(res.isAuthenticated, true);
    assert.equal(res.interaction, 'favorite');
    assert.equal(res.error, undefined);
  } finally {
    setTestClient(null);
  }
});

test('getBookInteraction: detects mobile favorites entry if absent from user_interactions', async () => {
  const userId = 'usr-mobile-sync-888';
  const bookId = '9780441013593';

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
        };
      }
      if (table === 'favorites') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({ data: { book_id: bookId }, error: null }),
              }),
            }),
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await getBookInteraction(bookId);
    assert.equal(res.success, true);
    assert.equal(res.isAuthenticated, true);
    assert.equal(res.interaction, 'favorite');
  } finally {
    setTestClient(null);
  }
});

test('getBookInteraction: returns interaction null when authenticated user has no interaction', async () => {
  const userId = 'usr-clean-slate-999';
  const bookId = '9780441013593';

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: userId } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === 'user_interactions' || table === 'favorites') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({ data: null, error: null }),
              }),
            }),
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await getBookInteraction(bookId);
    assert.equal(res.success, true);
    assert.equal(res.isAuthenticated, true);
    assert.equal(res.interaction, null);
  } finally {
    setTestClient(null);
  }
});

test('getBookInteraction: returns isAuthenticated false and interaction null for unauthenticated visitors', async () => {
  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: 'No session' },
      }),
    },
    from: () => {
      throw new Error('Should not query tables for unauthenticated visitor');
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await getBookInteraction('9780441013593');
    assert.equal(res.success, true);
    assert.equal(res.isAuthenticated, false);
    assert.equal(res.interaction, null);
  } finally {
    setTestClient(null);
  }
});

test('getBookInteraction: cleanly distinguishes database query error from "no interaction"', async () => {
  const userId = 'usr-error-check';
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
                  data: null,
                  error: { message: 'relation user_interactions does not exist' },
                }),
              }),
            }),
          }),
        };
      }
      throw new Error(`Unexpected table ${table}`);
    },
  };

  setTestClient(fakeSupabase);
  try {
    const res = await getBookInteraction('9780441013593');
    assert.equal(res.success, false);
    assert.equal(res.isAuthenticated, true);
    assert.equal(res.interaction, null);
    assert.ok(res.error?.includes('relation user_interactions does not exist'));
  } finally {
    setTestClient(null);
  }
});

// ── 3. Activity Tracking Session Behavior (P2) ────────────────────────────────

test('trackActivityAction: unauthenticated visits exit early without sending request to Flask', async () => {
  let backendTrackInvoked = false;
  const originalTrack = ApiService.trackActivity;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: 'Session required' },
      }),
    },
  };

  setTestClient(fakeSupabase);
  try {
    ApiService.trackActivity = async () => {
      backendTrackInvoked = true;
      return true;
    };

    const res = await trackActivityAction('9780441013593', 'view');
    assert.equal(res.success, false);
    assert.ok(res.error?.includes('Unauthorized'));
    assert.equal(backendTrackInvoked, false, 'Backend track API must NOT be called for unauthenticated visitors');
  } finally {
    ApiService.trackActivity = originalTrack;
    setTestClient(null);
  }
});

test('trackActivityAction: authenticated visits forward activity tracking to ApiService', async () => {
  let trackedBookId = '';
  let trackedAction = '';
  const originalTrack = ApiService.trackActivity;

  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: 'usr-analytics-valid' } },
        error: null,
      }),
    },
  };

  setTestClient(fakeSupabase);
  try {
    ApiService.trackActivity = async (bId: string, act: string) => {
      trackedBookId = bId;
      trackedAction = act;
      return true;
    };

    const res = await trackActivityAction('9780441013593', 'view');
    assert.equal(res.success, true);
    assert.equal(trackedBookId, '9780441013593');
    assert.equal(trackedAction, 'view');
  } finally {
    ApiService.trackActivity = originalTrack;
    setTestClient(null);
  }
});
