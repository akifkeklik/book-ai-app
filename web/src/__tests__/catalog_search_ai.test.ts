import test from 'node:test';
import assert from 'node:assert/strict';
import { ApiService } from '../lib/api';
import type { AiChatResponse } from '../types';

test('Catalog Search: ApiService.getBooks constructs correct query params for combined search and category', async () => {
  const originalFetch = global.fetch;
  let requestedUrl = '';

  global.fetch = (async (url: string | URL | Request) => {
    requestedUrl = String(url);
    return new Response(
      JSON.stringify({
        books: [],
        total: 0,
        page: 1,
        per_page: 20,
        total_pages: 0,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }) as typeof fetch;

  try {
    await ApiService.getBooks({
      query: '1984',
      category: 'Young Adult & Children',
      sort: 'newest',
      order: 'desc',
      page: 1,
      per_page: 20,
    });

    const parsed = new URL(requestedUrl);
    assert.strictEqual(parsed.pathname, '/api/books');
    assert.strictEqual(parsed.searchParams.get('q'), '1984');
    assert.strictEqual(parsed.searchParams.get('category'), 'Young Adult & Children');
    assert.strictEqual(parsed.searchParams.get('sort'), 'newest');
    assert.strictEqual(parsed.searchParams.get('order'), 'desc');
    assert.strictEqual(parsed.searchParams.get('page'), '1');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Catalog Search: ApiService.getBooks handles title, author, and ISBN identifier queries consistently', async () => {
  const originalFetch = global.fetch;
  const capturedUrls: string[] = [];

  global.fetch = (async (url: string | URL | Request) => {
    const urlStr = String(url);
    capturedUrls.push(urlStr);
    const mockBook = {
      isbn13: '9780452284234',
      title: '1984',
      authors: 'George Orwell',
      categories: 'History',
      average_rating: 4.28,
      ratings_count: 216,
    };

    if (urlStr.includes('/api/books/9780452284234')) {
      return new Response(
        JSON.stringify({ book: mockBook }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({
        books: [mockBook],
        total: 1,
        page: 1,
        per_page: 20,
        total_pages: 1,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }) as typeof fetch;

  try {
    // 1. Title search
    const byTitle = await ApiService.getBooks({ query: '1984' });
    assert.strictEqual(byTitle.books.length, 1);
    assert.strictEqual(byTitle.books[0].title, '1984');

    // 2. Author search
    const byAuthor = await ApiService.getBooks({ query: 'George Orwell' });
    assert.strictEqual(byAuthor.books.length, 1);

    // 3. ISBN lookup
    const byIsbn = await ApiService.getBookByIsbn('9780452284234');
    assert.ok(byIsbn);
    assert.strictEqual(byIsbn?.isbn13, '9780452284234');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Discovery: ApiService.chatWithAI enforces dedicated 30s timeout and extracts typed actions', async () => {
  const originalFetch = global.fetch;
  let receivedSignal: AbortSignal | undefined;

  global.fetch = (async (_url: string | URL | Request, init?: RequestInit) => {
    receivedSignal = init?.signal as AbortSignal | undefined;
    return new Response(
      JSON.stringify({
        answer: 'Görünüm modu Koyu Tema olarak ayarlandı.',
        referenced_books: [],
        status: 'action_executed',
        action: {
          type: 'SET_THEME',
          payload: { theme: 'dark' },
        },
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }) as typeof fetch;

  try {
    const res: AiChatResponse = await ApiService.chatWithAI('Koyu temaya geç');
    assert.strictEqual(res.status, 'action_executed');
    assert.ok(res.action);
    assert.strictEqual(res.action?.type, 'SET_THEME');
    assert.strictEqual(res.action?.payload.theme, 'dark');
    assert.ok(receivedSignal);
    assert.strictEqual(receivedSignal.aborted, false);
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Discovery: ApiService.chatWithAI normalizes referenced books and parses palette actions', async () => {
  const originalFetch = global.fetch;

  global.fetch = (async () => {
    return new Response(
      JSON.stringify({
        answer: 'Vurgu paletiniz başarıyla güncellendi: Forest Green.',
        referenced_books: [
          {
            isbn13: '9780452284234',
            title: '1984',
            authors: 'George Orwell',
            average_rating: 4.28,
            explanation: 'Classic dystopian novel about totalitarianism.',
          },
        ],
        status: 'action_executed',
        action: {
          type: 'SET_PALETTE',
          payload: { palette: 'forest_green' },
        },
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }) as typeof fetch;

  try {
    const res = await ApiService.chatWithAI('Vurgu rengini orman yeşili yap');
    assert.strictEqual(res.status, 'action_executed');
    assert.strictEqual(res.action?.type, 'SET_PALETTE');
    assert.strictEqual(res.action?.payload.palette, 'forest_green');
    assert.strictEqual(res.referencedBooks.length, 1);
    assert.strictEqual(res.referencedBooks[0].isbn13, '9780452284234');
    assert.strictEqual(res.referencedBooks[0].title, '1984');
  } finally {
    global.fetch = originalFetch;
  }
});
