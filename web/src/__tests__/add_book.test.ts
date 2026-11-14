import test from 'node:test';
import assert from 'node:assert/strict';
import { ApiService } from '../lib/api';
import { guessGenre } from '../components/AddBookModal';

function withFetch(handler: (url: string, init?: RequestInit) => Response) {
  const original = globalThis.fetch;
  globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => handler(url.toString(), init)) as typeof fetch;
  return () => {
    globalThis.fetch = original;
  };
}

test('lookupBooks normalizes candidates and flags books already in the catalog', async () => {
  let calledUrl = '';
  const restore = withFetch((url) => {
    calledUrl = url;
    return new Response(
      JSON.stringify({
        results: [
          { isbn13: '9780374275631', title: 'Thinking, Fast and Slow', authors: 'Daniel Kahneman', categories: 'Psychology', page_count: 499, published_date: '2011', thumbnail: 'https://books.google.com/x', in_catalog_isbn: null },
          { isbn13: '9780000000101', title: 'Atomic Habits', authors: 'James Clear', in_catalog_isbn: '9780000000101' },
        ],
      }),
      { status: 200 }
    );
  });
  try {
    const results = await ApiService.lookupBooks('thinking fast');
    assert.match(calledUrl, /\/api\/books\/lookup\?q=thinking\+fast$/);
    assert.equal(results[0].pageCount, 499);
    assert.equal(results[0].inCatalogIsbn, null);
    assert.equal(results[1].inCatalogIsbn, '9780000000101');
  } finally {
    restore();
  }
});

test('addCatalogBook sends snake_case fields and reports created/persisted', async () => {
  let body: Record<string, unknown> = {};
  const restore = withFetch((_url, init) => {
    body = JSON.parse(String(init?.body));
    return new Response(
      JSON.stringify({ book: { isbn13: 'lb0123456789abcdef', title: 'Zine', authors: 'Me' }, created: true, persisted: false }),
      { status: 201 }
    );
  });
  try {
    const res = await ApiService.addCatalogBook({ title: 'Zine', authors: 'Me', pageCount: 40, publishedDate: '2024' });
    assert.equal(body.page_count, 40);
    assert.equal(body.published_date, '2024');
    assert.equal(res.book.isbn13, 'lb0123456789abcdef');
    assert.equal(res.created, true);
    assert.equal(res.persisted, false);
  } finally {
    restore();
  }
});

test('addCatalogBook surfaces backend validation errors', async () => {
  const restore = withFetch(() => new Response(JSON.stringify({ error: 'title is required' }), { status: 400 }));
  try {
    await assert.rejects(ApiService.addCatalogBook({ title: '', authors: 'A' }), /title is required/);
  } finally {
    restore();
  }
});

test('guessGenre maps free-text categories to a catalog genre', () => {
  assert.equal(guessGenre('Psychology / Cognitive'), 'Psychology');
  assert.equal(guessGenre('Business & Economics'), 'Business');
  assert.equal(guessGenre(''), '');
  assert.equal(guessGenre('Zzz unknown'), '');
});
