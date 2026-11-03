import test from 'node:test';
import assert from 'node:assert/strict';
import { ApiService } from '../lib/api';

test('Next.js Catalog Caching: getCategories passes public headers and explicit Next.js cache configuration', async () => {
  const originalFetch = globalThis.fetch;
  const originalEnv = process.env;
  process.env = { ...originalEnv, BACKEND_URL: 'http://mock-libris.local', LIBRIS_API_KEY: 'test-api-key' };

  let capturedUrl = '';
  let capturedInit: RequestInit | undefined;

  try {
    globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => {
      capturedUrl = url.toString();
      capturedInit = init;
      return new Response(JSON.stringify({ categories: [{ name: 'Fiction', count: 120 }] }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }) as unknown as typeof fetch;

    const categories = await ApiService.getCategories();
    assert.equal(categories.length, 1);
    assert.equal(categories[0].name, 'Fiction');

    assert.ok(capturedUrl.endsWith('/api/categories'));
    assert.ok(capturedInit);

    // Verify public headers: X-Api-Key present, NO Authorization header
    const headers = capturedInit?.headers as Record<string, string>;
    assert.equal(headers['X-Api-Key'], 'test-api-key');
    assert.equal(headers['Authorization'], undefined);

    // Verify Next.js cache tags and revalidation
    const nextOpts = (capturedInit as Record<string, unknown>)?.next as { revalidate?: number; tags?: string[] };
    assert.ok(nextOpts);
    assert.equal(nextOpts.revalidate, 3600);
    assert.ok(nextOpts.tags?.includes('categories'));
  } finally {
    globalThis.fetch = originalFetch;
    process.env = originalEnv;
  }
});

test('Next.js Catalog Caching: getBooks sets category-specific cache tags and preserves query parameters', async () => {
  const originalFetch = globalThis.fetch;
  const originalEnv = process.env;
  process.env = { ...originalEnv, BACKEND_URL: 'http://mock-libris.local', LIBRIS_API_KEY: 'test-api-key' };

  let capturedUrl = '';
  let capturedInit: RequestInit | undefined;

  try {
    globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => {
      capturedUrl = url.toString();
      capturedInit = init;
      return new Response(
        JSON.stringify({
          books: [{ isbn13: '9780141439518', title: 'Pride and Prejudice', authors: 'Jane Austen' }],
          total: 1,
          total_pages: 1,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }) as unknown as typeof fetch;

    const res = await ApiService.getBooks({
      page: 2,
      per_page: 20,
      category: 'Science Fiction',
      query: 'asimov',
      sort: 'rating',
      order: 'desc',
      min_rating: 4.0,
    });

    assert.equal(res.books.length, 1);
    assert.equal(res.total, 1);

    // Verify distinct URL params
    const parsedUrl = new URL(capturedUrl);
    assert.equal(parsedUrl.searchParams.get('page'), '2');
    assert.equal(parsedUrl.searchParams.get('category'), 'Science Fiction');
    assert.equal(parsedUrl.searchParams.get('q'), 'asimov');
    assert.equal(parsedUrl.searchParams.get('sort'), 'rating');
    assert.equal(parsedUrl.searchParams.get('order'), 'desc');
    assert.equal(parsedUrl.searchParams.get('min_rating'), '4');

    // Verify public headers (zero authorization leak)
    const headers = capturedInit?.headers as Record<string, string>;
    assert.equal(headers['Authorization'], undefined);

    // Verify Next.js catalog cache tags
    const nextOpts = (capturedInit as Record<string, unknown>)?.next as { revalidate?: number; tags?: string[] };
    assert.equal(nextOpts.revalidate, 300);
    assert.ok(nextOpts.tags?.includes('catalog'));
    assert.ok(nextOpts.tags?.includes('catalog-science%20fiction'));
  } finally {
    globalThis.fetch = originalFetch;
    process.env = originalEnv;
  }
});

test('Next.js Catalog Caching: getBookByIsbn includes specific book tag and does not leak auth token', async () => {
  const originalFetch = globalThis.fetch;
  const originalEnv = process.env;
  process.env = { ...originalEnv, BACKEND_URL: 'http://mock-libris.local', LIBRIS_API_KEY: 'test-api-key' };

  let capturedUrl = '';
  let capturedInit: RequestInit | undefined;

  try {
    globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => {
      capturedUrl = url.toString();
      capturedInit = init;
      return new Response(
        JSON.stringify({
          book: { isbn13: '9780452284234', title: '1984', authors: 'George Orwell' },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }) as unknown as typeof fetch;

    const book = await ApiService.getBookByIsbn('978-0-452-28423-4');
    assert.ok(book !== null);
    assert.equal(book?.isbn13, '9780452284234');

    assert.ok(capturedUrl.endsWith('/api/books/9780452284234'));
    const headers = capturedInit?.headers as Record<string, string>;
    assert.equal(headers['Authorization'], undefined);

    const nextOpts = (capturedInit as Record<string, unknown>)?.next as { revalidate?: number; tags?: string[] };
    assert.equal(nextOpts.revalidate, 3600);
    assert.ok(nextOpts.tags?.includes('books'));
    assert.ok(nextOpts.tags?.includes('book-9780452284234'));
  } finally {
    globalThis.fetch = originalFetch;
    process.env = originalEnv;
  }
});

test('Next.js Catalog Caching: authenticated personalized endpoints strictly enforce cache: "no-store"', async () => {
  const originalFetch = globalThis.fetch;
  let capturedInit: RequestInit | undefined;

  try {
    globalThis.fetch = (async (_url: string | URL | Request, init?: RequestInit) => {
      capturedInit = init;
      return new Response(
        JSON.stringify({ recommendations: [] }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }) as unknown as typeof fetch;

    await ApiService.getPersonalizedRecommendations(5);

    assert.equal(capturedInit?.cache, 'no-store');
    const nextOpts = (capturedInit as Record<string, unknown>)?.next;
    assert.equal(nextOpts, undefined); // Must NOT specify shared cache tags
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Next.js Catalog Caching: feedback and tracking mutations enforce cache: "no-store"', async () => {
  const originalFetch = globalThis.fetch;
  let feedbackInit: RequestInit | undefined;
  let trackInit: RequestInit | undefined;

  try {
    globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => {
      const urlStr = url.toString();
      if (urlStr.includes('/api/feedback')) feedbackInit = init;
      if (urlStr.includes('/api/track')) trackInit = init;
      return new Response(JSON.stringify({ status: 'success' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }) as unknown as typeof fetch;

    await ApiService.submitFeedback('9780452284234', 'reading');
    await ApiService.trackActivity('9780452284234', 'view');

    assert.equal(feedbackInit?.cache, 'no-store');
    assert.equal(feedbackInit?.method, 'POST');
    assert.equal(trackInit?.cache, 'no-store');
    assert.equal(trackInit?.method, 'POST');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Next.js Catalog Caching: safe fallback when backend fails: getBookByIsbn returns null on 404 and throws controlled error on 500', async () => {
  const originalFetch = globalThis.fetch;

  try {
    globalThis.fetch = (async () => {
      return new Response('Not Found', { status: 404 });
    }) as unknown as typeof fetch;

    const notFoundBook = await ApiService.getBookByIsbn('9780000000000');
    assert.equal(notFoundBook, null);

    globalThis.fetch = (async () => {
      return new Response('Internal Server Error', { status: 500 });
    }) as unknown as typeof fetch;

    await assert.rejects(
      async () => {
        await ApiService.getBookByIsbn('9780000000000');
      },
      (err: Error) => {
        assert.match(err.message, /Failed to fetch book details \(500\)/);
        return true;
      }
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
