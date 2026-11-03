import test from 'node:test';
import assert from 'node:assert/strict';
import {
  submitReviewAction,
} from '../app/actions/notes';
import { ApiService } from '../lib/api';
import { DICTIONARIES } from '../lib/i18n';

test('ApiService.getDueReviews: calls backend and normalizes NoteReview DTOs', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedUrl = '';
    globalThis.fetch = async (url: string | URL | Request) => {
      capturedUrl = url.toString();
      return new Response(
        JSON.stringify({
          status: 'success',
          reviews: [
            {
              id: 'rev-1',
              note_id: 'note-1',
              user_id: 'user-1',
              stage: 1,
              next_review_at: '2026-10-28T09:00:00Z',
              interval_days: 1,
              is_active: true,
              total_reviews: 0,
              successful_reviews: 0,
              note: {
                id: 'note-1',
                user_id: 'user-1',
                book_id: '9780141439518',
                note_type: 'key_takeaway',
                content: 'Pride is our biggest blindspot.',
                created_at: '2026-10-27T10:00:00Z',
                book: {
                  isbn13: '9780141439518',
                  title: 'Pride and Prejudice',
                  authors: 'Jane Austen',
                },
              },
            },
          ],
          total_due: 1,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const reviews = await ApiService.getDueReviews(10);
    assert.ok(capturedUrl.includes('/api/notes/reviews/due?limit=10'));
    assert.equal(reviews.length, 1);
    const rev = reviews[0];
    assert.equal(rev.id, 'rev-1');
    assert.equal(rev.stage, 1);
    assert.equal(rev.noteId, 'note-1');
    assert.equal(rev.note?.noteType, 'key_takeaway');
    assert.equal(rev.note?.book?.title, 'Pride and Prejudice');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.getReviewStats: returns summary stats', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => {
      return new Response(
        JSON.stringify({
          status: 'success',
          stats: {
            total: 12,
            due: 3,
            upcoming: 7,
            completed: 2,
          },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const stats = await ApiService.getReviewStats();
    assert.equal(stats.total, 12);
    assert.equal(stats.due, 3);
    assert.equal(stats.upcoming, 7);
    assert.equal(stats.completed, 2);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.submitReview: posts remembered outcome and normalizes updated review', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedMethod = '';
    let capturedUrl = '';
    let capturedBody = '';

    globalThis.fetch = async (url: string | URL | Request, init?: RequestInit) => {
      capturedUrl = url.toString();
      capturedMethod = init?.method || '';
      capturedBody = String(init?.body || '');
      return new Response(
        JSON.stringify({
          status: 'success',
          review: {
            id: 'rev-1',
            note_id: 'note-1',
            user_id: 'user-1',
            stage: 2,
            next_review_at: '2026-10-31T09:00:00Z',
            interval_days: 3,
            is_active: true,
            total_reviews: 1,
            successful_reviews: 1,
          },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const review = await ApiService.submitReview('note-1', 'remembered');
    assert.equal(capturedMethod, 'POST');
    assert.ok(capturedUrl.includes('/api/notes/note-1/review'));
    assert.ok(capturedBody.includes('"outcome":"remembered"'));
    assert.equal(review.stage, 2);
    assert.equal(review.intervalDays, 3);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.updateReviewSettings: updates review active status', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedMethod = '';
    let capturedBody = '';

    globalThis.fetch = async (url: string | URL | Request, init?: RequestInit) => {
      capturedMethod = init?.method || '';
      capturedBody = String(init?.body || '');
      return new Response(
        JSON.stringify({
          status: 'success',
          review: {
            id: 'rev-1',
            note_id: 'note-1',
            user_id: 'user-1',
            stage: 1,
            next_review_at: '2026-10-28T09:00:00Z',
            interval_days: 1,
            status: 'paused',
          },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const review = await ApiService.updateReviewSettings('note-1', 'paused');
    assert.equal(capturedMethod, 'PUT');
    assert.ok(capturedBody.includes('"status":"paused"'));
    assert.equal(review.status, 'paused');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.exportNotes: retrieves markdown with Turkish UTF-8 preservation', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedUrl = '';
    globalThis.fetch = async (url: string | URL | Request) => {
      capturedUrl = url.toString();
      return new Response(
        JSON.stringify({
          status: 'success',
          content: '# Kişisel Öğrenme Notları\n\n## Saatleri Ayarlama Enstitüsü\n- **Önemli Çıkarım:** Hayat akışı.',
          filename: 'libris_notlar_9789759955748.md',
          mime_type: 'text/markdown; charset=utf-8',
          total: 1,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json; charset=utf-8' } }
      );
    };

    const res = await ApiService.exportNotes('9789759955748');
    assert.ok(capturedUrl.includes('/api/notes/export?book_id=9789759955748'));
    assert.equal(res.total, 1);
    assert.equal(res.filename, 'libris_notlar_9789759955748.md');
    assert.ok(res.content.includes('Kişisel Öğrenme Notları'));
    assert.ok(res.content.includes('Saatleri Ayarlama Enstitüsü'));
    assert.ok(res.content.includes('Önemli Çıkarım'));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('submitReviewAction: validates inputs before API request', async () => {
  // Empty noteId
  const res1 = await submitReviewAction('', 'remembered');
  assert.equal(res1.success, false);
  assert.ok(res1.error?.includes('noteId'));

  // Missing outcome
  const res2 = await submitReviewAction('note-1', '' as unknown as 'remembered');
  assert.equal(res2.success, false);
  assert.ok(res2.error?.includes('outcome'));
});

test('i18n: review and export keys exist across all languages', () => {
  const requiredKeys = [
    'smart_review_title',
    'smart_review_subtitle',
    'smart_review_empty',
    'smart_review_remembered',
    'smart_review_struggled',
    'smart_review_due_count',
    'export_notes',
    'export_notes_desc',
    'copy_markdown',
    'markdown_copied',
    'download_markdown',
    'print_preview',
    'smart_review_stage',
  ] as const;

  for (const lang of ['en', 'tr', 'de'] as const) {
    const langDict = DICTIONARIES[lang];
    assert.ok(langDict, `Dictionary missing for language "${lang}"`);
    for (const key of requiredKeys) {
      assert.ok(
        (langDict as Record<string, string>)[key] !== undefined,
        `Missing translation key "${key}" in language "${lang}"`
      );
      assert.ok(
        (langDict as Record<string, string>)[key].trim().length > 0,
        `Empty translation for "${key}" in language "${lang}"`
      );
    }
  }
});

