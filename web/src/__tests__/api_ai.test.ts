import test from 'node:test';
import assert from 'node:assert/strict';
import { ApiService } from '../lib/api';

test('ApiService.chatWithAI: consumes canonical referenced_books and normalizes book DTOs', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async (url: string | URL | Request, init?: RequestInit) => {
      assert.ok(String(url).includes('/api/ai/chat'));
      assert.equal(init?.method, 'POST');
      const body = JSON.parse(init?.body as string);
      assert.equal(body.query, 'Find sci-fi books');

      return new Response(
        JSON.stringify({
          answer: 'Here is a great sci-fi recommendation.',
          referenced_books: [
            {
              isbn13: '9780441013593',
              title: 'Dune',
              authors: 'Frank Herbert',
              average_rating: 4.8,
              ratings_count: 50000,
              published_date: '1965',
              page_count: 688,
              similarity_score: 0.94,
              recommendation_reason: 'Seminal science fiction masterpiece',
            },
          ],
          status: 'success',
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const res = await ApiService.chatWithAI('Find sci-fi books');

    assert.equal(res.answer, 'Here is a great sci-fi recommendation.');
    assert.equal(res.status, 'success');
    assert.equal(res.referencedBooks.length, 1);

    const book = res.referencedBooks[0];
    assert.equal(book.isbn13, '9780441013593');
    assert.equal(book.title, 'Dune');
    assert.equal(book.authors, 'Frank Herbert');
    assert.equal(book.averageRating, 4.8);
    assert.equal(book.ratingsCount, 50000);
    assert.equal(book.publishedDate, '1965');
    assert.equal(book.pageCount, 688);
    assert.equal(book.similarityScore, 0.94);
    assert.equal(book.recommendationReason, 'Seminal science fiction masterpiece');

    // Backward-compatibility field also matches
    assert.equal(res.recommendations?.length, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.chatWithAI: handles empty referenced_books gracefully', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => {
      return new Response(
        JSON.stringify({
          answer: 'Hello! How can I help you discover books today?',
          referenced_books: [],
          status: 'success',
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const res = await ApiService.chatWithAI('Hello');

    assert.equal(res.answer, 'Hello! How can I help you discover books today?');
    assert.deepEqual(res.referencedBooks, []);
    assert.deepEqual(res.recommendations, []);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.chatWithAI: supports legacy recommendations field if referenced_books is omitted', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => {
      return new Response(
        JSON.stringify({
          answer: 'Legacy response structure',
          recommendations: [
            {
              isbn13: '9780345391803',
              title: "The Hitchhiker's Guide to the Galaxy",
              authors: 'Douglas Adams',
              average_rating: 4.22,
            },
          ],
          status: 'success',
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const res = await ApiService.chatWithAI('Sci-fi comedy');

    assert.equal(res.referencedBooks.length, 1);
    assert.equal(res.referencedBooks[0].title, "The Hitchhiker's Guide to the Galaxy");
    assert.equal(res.referencedBooks[0].averageRating, 4.22);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.chatWithAI: handles backend error responses cleanly', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => {
      return new Response(
        JSON.stringify({ error: 'Too Many Requests' }),
        { status: 429, headers: { 'Content-Type': 'application/json' } }
      );
    };

    await assert.rejects(
      async () => {
        await ApiService.chatWithAI('Too fast');
      },
      {
        name: 'Error',
        message: 'Too Many Requests',
      }
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.chatWithAI: handles malformed backend payload without throwing', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => {
      return new Response(
        JSON.stringify({}),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const res = await ApiService.chatWithAI('test');

    assert.equal(res.answer, '');
    assert.deepEqual(res.referencedBooks, []);
    assert.deepEqual(res.recommendations, []);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
