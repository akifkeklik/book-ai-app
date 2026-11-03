import test from 'node:test';
import assert from 'node:assert/strict';
import {
  getLibraryBooks,
  addFavoriteItem,
  removeFavoriteItem,
  updateLibraryItemStatus,
  removeLibraryItem,
  getBookInteraction,
} from '../app/actions/library';
import { ApiService } from '../lib/api';
import { setTestClient } from '../lib/supabase/server';

test('Unified Adapter: Unauthenticated requests are rejected before calling ApiService', async () => {
  const unauthClient = {
    auth: {
      getUser: async () => ({
        data: { user: null },
        error: { message: 'Unauthorized' },
      }),
    },
  };
  setTestClient(unauthClient);

  try {
    // Unauthenticated getLibraryBooks
    const libRes = await getLibraryBooks();
    assert.equal(libRes.success, false);
    assert.ok(libRes.error?.includes('Unauthorized'));
    assert.deepEqual(libRes.items, []);

  // Unauthenticated mutations
  const addRes = await addFavoriteItem('9780007111503');
  assert.equal(addRes.success, false);
  assert.ok(addRes.error?.includes('Unauthorized'));

  const remFavRes = await removeFavoriteItem('9780007111503');
  assert.equal(remFavRes.success, false);
  assert.ok(remFavRes.error?.includes('Unauthorized'));

  const updateRes = await updateLibraryItemStatus('9780007111503', 'reading');
  assert.equal(updateRes.success, false);
  assert.ok(updateRes.error?.includes('Unauthorized'));

  const remItemRes = await removeLibraryItem('9780007111503');
  assert.equal(remItemRes.success, false);
  assert.ok(remItemRes.error?.includes('Unauthorized'));

  // getBookInteraction returns unauthenticated state safely without error
  const interRes = await getBookInteraction('9780007111503');
  assert.equal(interRes.success, true);
  assert.equal(interRes.isAuthenticated, false);
  assert.equal(interRes.interaction, null);
    assert.equal(interRes.isFavorite, false);
  } finally {
    setTestClient(null);
  }
});

test('Unified Adapter: Input validation rejects invalid bookId and status values', async () => {
  const mockClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: 'test-user' } },
        error: null,
      }),
      getSession: async () => ({
        data: { session: { access_token: 'test-token' } },
      }),
    },
  };
  setTestClient(mockClient);

  try {

  // Invalid bookId inputs
  const res1 = await addFavoriteItem('');
  assert.equal(res1.success, false);
  assert.equal(res1.error, 'Invalid book ID');

  const res2 = await removeFavoriteItem('');
  assert.equal(res2.success, false);
  assert.equal(res2.error, 'Invalid book ID');

  const res3 = await removeLibraryItem('');
  assert.equal(res3.success, false);
  assert.equal(res3.error, 'Invalid book ID');

  const res4 = await getBookInteraction('');
  assert.equal(res4.success, false);
  assert.equal(res4.error, 'Invalid book ID');

  // Invalid collection status
  // @ts-expect-error testing invalid status
  const res5 = await updateLibraryItemStatus('9780007111503', 'invalid_status');
  assert.equal(res5.success, false);
  assert.ok(res5.error?.includes('Invalid collection status'));
  } finally {
    setTestClient(null);
  }
});

test('Unified Adapter: Authenticated calls delegate to ApiService methods', async () => {
  const originalGetLibrary = ApiService.getLibraryBooks;
  const originalSubmit = ApiService.submitFeedback;
  const originalGetInter = ApiService.getBookInteraction;

  const submitCalls: Array<{ bookId: string; interaction: string }> = [];
  let getLibraryCalled = false;
  let getInterCalledWith: string | null = null;

  // Mock ApiService methods
  ApiService.getLibraryBooks = async () => {
    getLibraryCalled = true;
    return [
      {
        id: '9780007111503',
        bookId: '9780007111503',
        status: 'reading',
        isFavorite: true,
        addedAt: '2026-02-01T12:00:00Z',
        book: {
          isbn13: '9780007111503',
          title: 'Partners in Crime',
          authors: 'Agatha Christie',
          categories: 'Detective',
          description: '',
          thumbnail: '',
          averageRating: 4.0,
          ratingsCount: 10,
          publishedDate: '',
          pageCount: 300,
        },
      },
    ];
  };

  ApiService.submitFeedback = async (bookId, interaction) => {
    submitCalls.push({ bookId, interaction });
    return true;
  };

  ApiService.getBookInteraction = async (bookId) => {
    getInterCalledWith = bookId;
    return {
      interaction: 'reading',
      isFavorite: true,
      isAuthenticated: true,
    };
  };

  // Mock authenticated session
  const fakeAuthClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: 'user-adapter-test-123' } },
        error: null,
      }),
      getSession: async () => ({
        data: { session: { access_token: 'mock-test-jwt' } },
      }),
    },
  };

  setTestClient(fakeAuthClient);

  try {
    // 1. getLibraryBooks delegates to ApiService.getLibraryBooks
    const libRes = await getLibraryBooks();
    assert.equal(libRes.success, true);
    assert.equal(getLibraryCalled, true);
    assert.equal(libRes.items.length, 1);
    assert.equal(libRes.items[0].status, 'reading');
    assert.equal(libRes.items[0].isFavorite, true);

    // 2. addFavoriteItem delegates to ApiService.submitFeedback('favorite')
    const addRes = await addFavoriteItem('9780007111503');
    assert.equal(addRes.success, true);
    assert.deepEqual(submitCalls[0], { bookId: '9780007111503', interaction: 'favorite' });

    // 3. removeFavoriteItem delegates to ApiService.submitFeedback('unfavorite')
    const remFavRes = await removeFavoriteItem('9780007111503');
    assert.equal(remFavRes.success, true);
    assert.deepEqual(submitCalls[1], { bookId: '9780007111503', interaction: 'unfavorite' });

    // 4. updateLibraryItemStatus delegates to ApiService.submitFeedback(status)
    const updateRes = await updateLibraryItemStatus('9780007111503', 'finished');
    assert.equal(updateRes.success, true);
    assert.deepEqual(submitCalls[2], { bookId: '9780007111503', interaction: 'finished' });

    // 5. removeLibraryItem delegates to ApiService.submitFeedback('remove')
    const remItemRes = await removeLibraryItem('9780007111503');
    assert.equal(remItemRes.success, true);
    assert.deepEqual(submitCalls[3], { bookId: '9780007111503', interaction: 'remove' });

    // 6. getBookInteraction delegates to ApiService.getBookInteraction
    const interRes = await getBookInteraction('9780007111503');
    assert.equal(interRes.success, true);
    assert.equal(getInterCalledWith, '9780007111503');
    assert.equal(interRes.interaction, 'reading');
    assert.equal(interRes.isFavorite, true);
    assert.equal(interRes.isAuthenticated, true);
  } finally {
    setTestClient(null);
    ApiService.getLibraryBooks = originalGetLibrary;
    ApiService.submitFeedback = originalSubmit;
    ApiService.getBookInteraction = originalGetInter;
  }
});
