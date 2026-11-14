import test from 'node:test';
import assert from 'node:assert/strict';
import { ApiService } from '../lib/api';
import { formatRelativeReview } from '../components/RecallPreviewCard';

function mockNotesEndpoint(extra: Record<string, unknown>) {
  return async (url: string | URL | Request, init?: RequestInit) => {
    if (url.toString().includes('/api/notes')) {
      const body = JSON.parse(String(init?.body || '{}'));
      return new Response(
        JSON.stringify({
          status: 'success',
          note: { id: 'n-1', book_id: body.book_id, note_type: body.note_type, content: body.content },
          ...extra,
        }),
        { status: 201, headers: { 'Content-Type': 'application/json' } }
      );
    }
    return new Response('Not Found', { status: 404 });
  };
}

test('createNoteWithRecall returns the AI recall question saved with a takeaway', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = mockNotesEndpoint({
      recall_item: { id: 'r-1', question: '  Why does pride blind judgement?  ', next_review_at: '2026-11-15T09:00:00Z' },
    });
    const { note, recallItem } = await ApiService.createNoteWithRecall('9780141439518', 'key_takeaway', 'Pride blinds.');
    assert.equal(note.id, 'n-1');
    assert.deepEqual(recallItem, { id: 'r-1', question: 'Why does pride blind judgement?', nextReviewAt: '2026-11-15T09:00:00Z' });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('createNoteWithRecall returns null when no recall item was created', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = mockNotesEndpoint({});
    const { recallItem } = await ApiService.createNoteWithRecall('9780141439518', 'personal_note', 'Nice prose.');
    assert.equal(recallItem, null);

    globalThis.fetch = mockNotesEndpoint({ recall_item: { id: 'r-2', question: '   ' } });
    const empty = await ApiService.createNoteWithRecall('9780141439518', 'key_takeaway', 'x');
    assert.equal(empty.recallItem, null, 'blank questions are not shown');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('formatRelativeReview speaks the user language and handles bad input', () => {
  const now = new Date('2026-11-14T10:00:00');
  assert.equal(formatRelativeReview('2026-11-15T08:00:00', 'en', now), 'tomorrow');
  assert.equal(formatRelativeReview('2026-11-15T08:00:00', 'tr', now), 'yarın');
  assert.equal(formatRelativeReview('2026-11-17T08:00:00', 'en', now), 'in 3 days');
  assert.equal(formatRelativeReview(null, 'en', now), '');
  assert.equal(formatRelativeReview('not-a-date', 'en', now), '');
});
