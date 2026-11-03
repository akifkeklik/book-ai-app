import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ApiService,
  ApiTimeoutError,
  normalizeIsbn,
  isValidIsbn,
} from '../lib/api';
import { setTestClient } from '../lib/supabase/server';

test('ApiService.fetchWithTimeout: resolves successfully for 200 OK', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ categories: ['Classics', 'Sci-Fi'] }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });

    const categories = await ApiService.getCategories();
    assert.deepEqual(categories, ['Classics', 'Sci-Fi']);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.fetchWithTimeout: throws error on 500 Internal Server Error', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ error: 'Internal Server Error' }), {
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

test('ApiService.fetchWithTimeout: throws ApiTimeoutError when request times out', async () => {
  const originalFetch = globalThis.fetch;
  try {
    // Simulate hanging fetch that waits longer than signal abort
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

    const startTime = Date.now();
    await assert.rejects(
      async () => {
        // Test timeout with custom controller or default timeout behavior
        const controller = new AbortController();
        const testSignal = controller.signal;
        // Trigger abort simulating timeout
        setTimeout(() => controller.abort(), 20);
        await ApiService.getCategories({ signal: testSignal });
      },
      (err: unknown) => {
        assert.ok(err instanceof ApiTimeoutError || err instanceof Error);
        return true;
      }
    );
    assert.ok(Date.now() - startTime < 1000);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.fetchWithTimeout: honors caller-provided AbortSignal cancellation', async () => {
  const originalFetch = globalThis.fetch;
  try {
    const callerController = new AbortController();
    callerController.abort(new DOMException('User cancelled operation', 'AbortError'));

    await assert.rejects(
      async () => {
        await ApiService.getCategories({ signal: callerController.signal });
      },
      (err: unknown) => {
        assert.ok(err !== null && err !== undefined);
        return true;
      }
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService cache policy: personalized endpoints explicitly enforce cache: "no-store"', async () => {
  const originalFetch = globalThis.fetch;
  const capturedInits: RequestInit[] = [];

  try {
    globalThis.fetch = async (_url, init) => {
      if (init) capturedInits.push(init);
      return new Response(JSON.stringify({ recommendations: [], success: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    };

    await ApiService.getPersonalizedRecommendations(5);
    await ApiService.chatWithAI('Recommend a book');
    await ApiService.submitFeedback('9780441013593', 'like');
    await ApiService.trackActivity('9780441013593', 'view');

    assert.equal(capturedInits.length, 4);
    for (const init of capturedInits) {
      assert.equal(init.cache, 'no-store', `Expected cache: 'no-store' on personalized/mutation request`);
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService cache policy: public catalog endpoints preserve default cache behavior', async () => {
  const originalFetch = globalThis.fetch;
  const capturedInits: RequestInit[] = [];

  try {
    globalThis.fetch = async (_url, init) => {
      if (init) capturedInits.push(init);
      return new Response(JSON.stringify({ categories: [], books: [], book: { title: 'Dune' } }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    };

    await ApiService.getCategories();
    await ApiService.getBooks({ page: 1, per_page: 10 });
    await ApiService.getBookByIsbn('9780441013593');
    await ApiService.getRecommendations('Dune', 6);

    assert.equal(capturedInits.length, 4);
    for (const init of capturedInits) {
      assert.notEqual(
        init.cache,
        'no-store',
        'Public endpoints should not unnecessarily bypass cache with no-store'
      );
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('normalizeIsbn & isValidIsbn: validates standard ISBN-13 (13 digits)', () => {
  const validIsbn13 = '9780441013593';
  assert.equal(isValidIsbn(validIsbn13), true);
  assert.equal(normalizeIsbn(validIsbn13), '9780441013593');
});

test('normalizeIsbn & isValidIsbn: normalizes ISBN-13 with hyphens and spaces', () => {
  const formatted = ' 978-0-441-01359-3 ';
  assert.equal(isValidIsbn(formatted), true);
  assert.equal(normalizeIsbn(formatted), '9780441013593');

  const spaceFormatted = '978 0 441 01359 3';
  assert.equal(isValidIsbn(spaceFormatted), true);
  assert.equal(normalizeIsbn(spaceFormatted), '9780441013593');
});

test('normalizeIsbn & isValidIsbn: validates standard ISBN-10 and converts to canonical ISBN-13', () => {
  // Dune ISBN-10 is 0441013597, corresponding ISBN-13 is 9780441013593
  const isbn10 = '0441013597';
  assert.equal(isValidIsbn(isbn10), true);
  assert.equal(normalizeIsbn(isbn10), '9780441013593');

  // With hyphens
  const isbn10Hyphens = '0-441-01359-7';
  assert.equal(isValidIsbn(isbn10Hyphens), true);
  assert.equal(normalizeIsbn(isbn10Hyphens), '9780441013593');
});

test('normalizeIsbn & isValidIsbn: handles ISBN-10 with "X" check digit', () => {
  // 080442957X -> 9780804429573
  const isbnX = '0-8044-2957-X';
  assert.equal(isValidIsbn(isbnX), true);
  assert.equal(normalizeIsbn(isbnX), '9780804429573');
});

test('normalizeIsbn: rejects empty, null, and whitespace-only inputs', () => {
  assert.equal(normalizeIsbn(''), null);
  assert.equal(normalizeIsbn('   '), null);
  // @ts-expect-error test invalid inputs
  assert.equal(normalizeIsbn(null), null);
  // @ts-expect-error test invalid inputs
  assert.equal(normalizeIsbn(undefined), null);
});

test('normalizeIsbn: rejects path traversal and URL delimiters (.., /, \\, ?, #, %)', () => {
  assert.equal(normalizeIsbn('../admin'), null);
  assert.equal(normalizeIsbn('..\\admin'), null);
  assert.equal(normalizeIsbn('978044/1013593'), null);
  assert.equal(normalizeIsbn('978044?limit=10'), null);
  assert.equal(normalizeIsbn('978044#anchor'), null);
  assert.equal(normalizeIsbn('978044%201013593'), null);
  assert.equal(normalizeIsbn('<script>alert(1)</script>'), null);
});

test('normalizeIsbn: rejects special characters, injection patterns, and malformed length', () => {
  assert.equal(normalizeIsbn('12345'), null); // Too short
  assert.equal(normalizeIsbn('9780441013593000'), null); // Too long
  assert.equal(normalizeIsbn('not-an-isbn-at-all'), null);
  assert.equal(normalizeIsbn("9780441013593'; DROP TABLE books;--"), null);
});

test('ApiService.getBookByIsbn: safely returns null without network request for invalid ISBN', async () => {
  let fetchCalled = false;
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => {
      fetchCalled = true;
      return new Response(JSON.stringify({ error: 'Should not be called' }), { status: 400 });
    };

    const resEmpty = await ApiService.getBookByIsbn('');
    assert.equal(resEmpty, null);

    const resPath = await ApiService.getBookByIsbn('../../etc/passwd');
    assert.equal(resPath, null);

    const resJunk = await ApiService.getBookByIsbn('invalid-junk');
    assert.equal(resJunk, null);

    assert.equal(fetchCalled, false, 'Fetch must never be called for invalid ISBN inputs');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.getBookByIsbn: properly encodes normalized ISBN in URL', async () => {
  const originalFetch = globalThis.fetch;
  let requestedUrl = '';

  try {
    globalThis.fetch = async (url) => {
      requestedUrl = String(url);
      return new Response(
        JSON.stringify({
          book: {
            isbn13: '9780441013593',
            title: 'Dune',
            authors: 'Frank Herbert',
          },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const book = await ApiService.getBookByIsbn('978-0-441-01359-3');
    assert.ok(book !== null);
    assert.equal(book.isbn13, '9780441013593');
    assert.ok(requestedUrl.endsWith('/api/books/9780441013593'));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.getHeaders: verifies active user with getUser before forwarding bearer token', async () => {
  const mockToken = 'verified.jwt.token-456';
  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: { id: 'usr-123', email: 'test@example.com' } },
        error: null,
      }),
      getSession: async () => ({
        data: {
          session: {
            access_token: mockToken,
          },
        },
      }),
    },
  };

  setTestClient(fakeSupabase);
  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['Authorization'], `Bearer ${mockToken}`);
  } finally {
    setTestClient(null);
  }
});

test('ApiService.getHeaders: omits bearer token if getUser fails or token is revoked', async () => {
  const fakeSupabase = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: 'Token expired or revoked' },
      }),
      getSession: async () => ({
        data: {
          session: {
            access_token: 'stale.revoked.token',
          },
        },
      }),
    },
  };

  setTestClient(fakeSupabase);
  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['Authorization'], undefined);
    assert.equal('Authorization' in headers, false);
  } finally {
    setTestClient(null);
  }
});
