import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createLearningPathAction,
  getLearningPathDetailAction,
  deleteLearningPathAction,
  addBookToLearningPathAction,
  reorderLearningPathBooksAction,
} from '../app/actions/learning_paths';
import { ApiService } from '../lib/api';
import { DICTIONARIES } from '../lib/i18n';

test('ApiService.getLearningPaths: calls backend and normalizes LearningPath DTOs', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedUrl = '';
    globalThis.fetch = async (url: string | URL | Request) => {
      capturedUrl = url.toString();
      return new Response(
        JSON.stringify({
          status: 'success',
          paths: [
            {
              id: 'path-1',
              user_id: 'user-1',
              title: 'Stoicism & Ancient Philosophy',
              description: 'Core stoic texts',
              category: 'Philosophy',
              status: 'active',
              books: [
                {
                  book_id: '9780141439518',
                  order_index: 0,
                  reading_status: 'finished',
                },
                {
                  book_id: '9780451524935',
                  order_index: 1,
                  reading_status: 'reading',
                },
              ],
              total_books: 2,
              completed_books: 1,
              reading_books: 1,
              not_started_books: 0,
              progress_percent: 50,
              next_book_id: '9780451524935',
            },
          ],
          total: 1,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const paths = await ApiService.getLearningPaths('active');
    assert.ok(capturedUrl.includes('/api/learning-paths?status=active'));
    assert.equal(paths.length, 1);
    const p = paths[0];
    assert.equal(p.id, 'path-1');
    assert.equal(p.title, 'Stoicism & Ancient Philosophy');
    assert.equal(p.totalBooks, 2);
    assert.equal(p.completedBooks, 1);
    assert.equal(p.progressPercent, 50);
    assert.equal(p.nextBookId, '9780451524935');
    assert.equal(p.books.length, 2);
    assert.equal(p.books[0].readingStatus, 'finished');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.getLearningPathById: calls backend and normalizes detail with catalog books', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedUrl = '';
    globalThis.fetch = async (url: string | URL | Request) => {
      capturedUrl = url.toString();
      return new Response(
        JSON.stringify({
          status: 'success',
          path: {
            id: 'path-123',
            user_id: 'user-1',
            title: 'Modern Dystopia',
            category: 'Fiction',
            status: 'active',
            books: [
              {
                book_id: '9780451524935',
                order_index: 0,
                book: {
                  isbn13: '9780451524935',
                  title: '1984',
                  authors: 'George Orwell',
                },
                reading_status: 'reading',
                notes_count: 3,
                has_due_review: true,
              },
            ],
            total_books: 1,
            completed_books: 0,
            reading_books: 1,
            not_started_books: 0,
            progress_percent: 0,
            total_notes_count: 3,
            total_reviews_due: 1,
          },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const path = await ApiService.getLearningPathById('path-123');
    assert.ok(capturedUrl.includes('/api/learning-paths/path-123'));
    assert.equal(path.id, 'path-123');
    assert.equal(path.books[0].book?.title, '1984');
    assert.equal(path.books[0].notesCount, 3);
    assert.equal(path.books[0].hasDueReview, true);
    assert.equal(path.totalReviewsDue, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService.createLearningPath: posts new path payload', async () => {
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
          path: {
            id: 'new-path-uuid',
            user_id: 'u1',
            title: 'Machine Learning Deep Dive',
            category: 'Tech',
            status: 'active',
            books: [],
          },
        }),
        { status: 201, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const created = await ApiService.createLearningPath({
      title: 'Machine Learning Deep Dive',
      category: 'Tech',
      bookIds: ['9780141439518'],
    });

    assert.equal(capturedMethod, 'POST');
    assert.ok(capturedBody.includes('Machine Learning Deep Dive'));
    assert.equal(created.id, 'new-path-uuid');
    assert.equal(created.title, 'Machine Learning Deep Dive');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('ApiService path book mutations: add, remove, and reorder', async () => {
  const originalFetch = globalThis.fetch;
  try {
    let capturedAddUrl = '';
    let capturedRemUrl = '';
    let capturedReorderBody = '';

    globalThis.fetch = async (url: string | URL | Request, init?: RequestInit) => {
      const u = url.toString();
      const m = init?.method || '';
      if (u.includes('/books/9780451524935') && m === 'DELETE') {
        capturedRemUrl = u;
        return new Response(JSON.stringify({ status: 'success', path: { id: 'p1', books: [] } }), { status: 200 });
      }
      if (u.includes('/books') && m === 'POST') {
        capturedAddUrl = u;
        return new Response(JSON.stringify({ status: 'success', path: { id: 'p1', books: [{ book_id: '9780451524935' }] } }), { status: 200 });
      }
      if (u.includes('/reorder') && m === 'PUT') {
        capturedReorderBody = String(init?.body || '');
        return new Response(JSON.stringify({ status: 'success', path: { id: 'p1', books: [] } }), { status: 200 });
      }
      return new Response('Not Found', { status: 404 });
    };

    await ApiService.addBookToLearningPath('p1', '9780451524935');
    assert.ok(capturedAddUrl.includes('/api/learning-paths/p1/books'));

    await ApiService.removeBookFromLearningPath('p1', '9780451524935');
    assert.ok(capturedRemUrl.includes('/api/learning-paths/p1/books/9780451524935'));

    await ApiService.reorderLearningPathBooks('p1', ['b2', 'b1']);
    assert.ok(capturedReorderBody.includes('"book_ids":["b2","b1"]'));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Server Actions: validate inputs before network requests', async () => {
  // Empty title
  const res1 = await createLearningPathAction({ title: '' });
  assert.equal(res1.success, false);
  assert.ok(res1.error?.includes('Title'));

  // Empty pathId on detail
  const res2 = await getLearningPathDetailAction('');
  assert.equal(res2.success, false);
  assert.ok(res2.error?.includes('pathId'));

  // Empty pathId on delete
  const res3 = await deleteLearningPathAction('');
  assert.equal(res3.success, false);
  assert.ok(res3.error?.includes('pathId'));

  // Empty pathId or bookId on addBook
  const res4 = await addBookToLearningPathAction('', '9780141439518');
  assert.equal(res4.success, false);
  assert.ok(res4.error?.includes('pathId'));

  // Invalid bookIds on reorder
  const res5 = await reorderLearningPathBooksAction('p1', null as unknown as string[]);
  assert.equal(res5.success, false);
  assert.ok(res5.error?.includes('bookIds'));
});

test('i18n: learning path keys exist across all languages', () => {
  const requiredKeys = [
    'learning_paths_title',
    'learning_paths_subtitle',
    'create_path',
    'edit_path',
    'delete_path',
    'path_title_label',
    'path_desc_label',
    'path_category_label',
    'path_empty_title',
    'path_empty_desc',
    'path_books_count',
    'path_progress_label',
    'path_next_book',
    'path_all_completed',
    'add_to_path',
    'remove_from_path',
    'move_up',
    'move_down',
    'path_confirm_delete',
    'suggested_books',
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


test('LearningPaths: active path state resolution invariant preserves valid selection or falls back cleanly', () => {
  const resolveActivePathId = (prev: string | null, pathList: { id: string }[]): string | null => {
    if (pathList.length === 0) return null;
    return (prev && pathList.some((p) => p.id === prev)) ? prev : pathList[0].id;
  };

  const initialList = [{ id: 'path-1' }, { id: 'path-2' }, { id: 'path-3' }];
  
  // 1. Initial load with no prior selection selects first path
  assert.equal(resolveActivePathId(null, initialList), 'path-1');

  // 2. Refresh while path-2 is selected keeps path-2 active (no unwanted reset to path-1)
  assert.equal(resolveActivePathId('path-2', initialList), 'path-2');

  // 3. When selected path is deleted from backend, falls back gracefully to path-1
  const updatedList = [{ id: 'path-1' }, { id: 'path-3' }];
  assert.equal(resolveActivePathId('path-2', updatedList), 'path-1');

  // 4. When all paths are deleted, returns null without exception
  assert.equal(resolveActivePathId('path-1', []), null);
});
