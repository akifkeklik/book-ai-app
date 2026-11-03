import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createNote,
  updateNote,
  deleteNote,
  getBookNotes,
} from '../app/actions/notes';
import { ApiService } from '../lib/api';
import type { NoteType } from '../types';

test('createNote: validates inputs before network call', async () => {
  // Empty bookId
  const res1 = await createNote('', 'personal_note', 'Valid content');
  assert.equal(res1.success, false);
  assert.ok(res1.error?.includes('bookId'));

  // Invalid noteType
  const res2 = await createNote('9780141439518', 'invalid_type' as NoteType, 'Valid content');
  assert.equal(res2.success, false);
  assert.ok(res2.error?.includes('Invalid noteType'));

  // Empty content
  const res3 = await createNote('9780141439518', 'personal_note', '   ');
  assert.equal(res3.success, false);
  assert.ok(res3.error?.includes('empty'));

  // Excessive content (> 5000 chars)
  const longContent = 'x'.repeat(5001);
  const res4 = await createNote('9780141439518', 'personal_note', longContent);
  assert.equal(res4.success, false);
  assert.ok(res4.error?.includes('5000'));
});

test('updateNote: validates inputs and rejects invalid types or length', async () => {
  // Empty noteId
  const res1 = await updateNote('', 'Updated content');
  assert.equal(res1.success, false);

  // Empty content
  const res2 = await updateNote('note-123', '   ');
  assert.equal(res2.success, false);

  // Invalid noteType
  const res3 = await updateNote('note-123', 'Valid content', 'invalid_kind' as NoteType);
  assert.equal(res3.success, false);

  // Excessive content
  const res4 = await updateNote('note-123', 'y'.repeat(5001));
  assert.equal(res4.success, false);
});

test('deleteNote: requires noteId', async () => {
  const res = await deleteNote('');
  assert.equal(res.success, false);
  assert.ok(res.error?.includes('noteId'));
});

test('getBookNotes: returns safe failure when bookId is invalid', async () => {
  const res = await getBookNotes('   ');
  assert.equal(res.success, false);
  assert.deepEqual(res.notes, []);
});

test('ApiService.createNote: calls backend and normalizes note DTO', async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async (url: string | URL | Request, init?: RequestInit) => {
      const urlStr = url.toString();
      if (urlStr.includes('/api/notes')) {
        const body = JSON.parse(String(init?.body || '{}'));
        return new Response(
          JSON.stringify({
            status: 'success',
            note: {
              id: 'note-uuid-999',
              user_id: 'user-test',
              book_id: body.book_id,
              note_type: body.note_type,
              content: body.content,
              created_at: '2026-10-27T12:00:00Z',
              updated_at: '2026-10-27T12:00:00Z',
              book: {
                isbn13: body.book_id,
                title: 'Sample Book',
                authors: 'Sample Author',
              },
            },
          }),
          { status: 201, headers: { 'Content-Type': 'application/json' } }
        );
      }
      return new Response('Not Found', { status: 404 });
    };

    const note = await ApiService.createNote('9780141439518', 'key_takeaway', 'Pride blinds us.');
    assert.equal(note.id, 'note-uuid-999');
    assert.equal(note.noteType, 'key_takeaway');
    assert.equal(note.bookId, '9780141439518');
    assert.equal(note.content, 'Pride blinds us.');
    assert.equal(note.book?.title, 'Sample Book');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.getNotes: supports filters, search query, and pagination', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedUrl = '';
    globalThis.fetch = async (url: string | URL | Request) => {
      capturedUrl = url.toString();
      return new Response(
        JSON.stringify({
          status: 'success',
          notes: [
            {
              id: 'n1',
              user_id: 'user-1',
              book_id: 'book-1',
              note_type: 'question',
              content: 'What is entropy?',
              created_at: '2026-10-27T10:00:00Z',
            },
          ],
          total: 1,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const res = await ApiService.getNotes({
      bookId: 'book-1',
      noteType: 'question',
      query: 'entropy',
      limit: 10,
      offset: 0,
    });

    assert.ok(capturedUrl.includes('book_id=book-1'));
    assert.ok(capturedUrl.includes('note_type=question'));
    assert.ok(capturedUrl.includes('q=entropy'));
    assert.ok(capturedUrl.includes('limit=10'));
    assert.equal(res.total, 1);
    assert.equal(res.notes[0].noteType, 'question');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.updateNote: propagates update to backend endpoint', async () => {
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
          note: {
            id: 'n1',
            user_id: 'u1',
            book_id: 'b1',
            note_type: 'personal_note',
            content: 'Revised content',
          },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const updated = await ApiService.updateNote('n1', 'Revised content');
    assert.equal(capturedMethod, 'PUT');
    assert.ok(capturedBody.includes('Revised content'));
    assert.equal(updated.content, 'Revised content');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.deleteNote: sends DELETE request to backend', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedMethod = '';
    let capturedUrl = '';
    globalThis.fetch = async (url: string | URL | Request, init?: RequestInit) => {
      capturedMethod = init?.method || '';
      capturedUrl = url.toString();
      return new Response(JSON.stringify({ status: 'success', deleted: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    };

    const ok = await ApiService.deleteNote('note-to-delete');
    assert.equal(ok, true);
    assert.equal(capturedMethod, 'DELETE');
    assert.ok(capturedUrl.includes('/api/notes/note-to-delete'));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

