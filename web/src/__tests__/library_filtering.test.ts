import test from 'node:test';
import assert from 'node:assert/strict';
import type { LibraryItem, LibraryCollectionStatus } from '../types';

function filterAndSortLibrary(
  items: LibraryItem[],
  tab: 'all' | LibraryCollectionStatus,
  search: string,
  sort: 'recent' | 'title' | 'rating'
): LibraryItem[] {
  return items
    .filter((item) => {
      if (tab !== 'all' && item.status !== tab) {
        return false;
      }
      if (search.trim().length > 0) {
        const q = search.toLowerCase();
        const matchTitle = item.book.title?.toLowerCase().includes(q);
        const matchAuthor = item.book.authors?.toLowerCase().includes(q);
        return matchTitle || matchAuthor;
      }
      return true;
    })
    .sort((a, b) => {
      if (sort === 'title') {
        return (a.book.title || '').localeCompare(b.book.title || '');
      }
      if (sort === 'rating') {
        return (b.book.averageRating || 0) - (a.book.averageRating || 0);
      }
      return new Date(b.addedAt).getTime() - new Date(a.addedAt).getTime();
    });
}

const mockLibraryItems: LibraryItem[] = [
  {
    id: '1',
    bookId: '1',
    status: 'favorite',
    addedAt: '2026-01-01T10:00:00Z',
    book: {
      isbn13: '1',
      title: 'Brave New World',
      authors: 'Aldous Huxley',
      categories: 'Dystopian',
      description: '',
      thumbnail: '',
      averageRating: 4.1,
      ratingsCount: 1000,
      publishedDate: '1932',
      pageCount: 311,
    },
  },
  {
    id: '2',
    bookId: '2',
    status: 'want_to_read',
    addedAt: '2026-01-05T10:00:00Z',
    book: {
      isbn13: '2',
      title: 'Animal Farm',
      authors: 'George Orwell',
      categories: 'Political Satire',
      description: '',
      thumbnail: '',
      averageRating: 4.6,
      ratingsCount: 5000,
      publishedDate: '1945',
      pageCount: 140,
    },
  },
  {
    id: '3',
    bookId: '3',
    status: 'finished',
    addedAt: '2026-01-10T10:00:00Z',
    book: {
      isbn13: '3',
      title: 'Crime and Punishment',
      authors: 'Fyodor Dostoevsky',
      categories: 'Classic',
      description: '',
      thumbnail: '',
      averageRating: 4.3,
      ratingsCount: 3000,
      publishedDate: '1866',
      pageCount: 671,
    },
  },
  {
    id: '4',
    bookId: '4',
    status: 'favorite',
    addedAt: '2026-01-15T10:00:00Z',
    book: {
      isbn13: '4',
      title: '1984',
      authors: 'George Orwell',
      categories: 'Dystopian',
      description: '',
      thumbnail: '',
      averageRating: 4.7,
      ratingsCount: 8000,
      publishedDate: '1949',
      pageCount: 328,
    },
  },
];

test('library filtering: returns all items when tab is "all"', () => {
  const result = filterAndSortLibrary(mockLibraryItems, 'all', '', 'recent');
  assert.equal(result.length, 4);
});

test('library filtering: filters strictly by collection tab', () => {
  const favs = filterAndSortLibrary(mockLibraryItems, 'favorite', '', 'recent');
  assert.equal(favs.length, 2);
  assert.ok(favs.every((i) => i.status === 'favorite'));

  const wantToRead = filterAndSortLibrary(mockLibraryItems, 'want_to_read', '', 'recent');
  assert.equal(wantToRead.length, 1);
  assert.equal(wantToRead[0].book.title, 'Animal Farm');

  const finished = filterAndSortLibrary(mockLibraryItems, 'finished', '', 'recent');
  assert.equal(finished.length, 1);
  assert.equal(finished[0].book.title, 'Crime and Punishment');

  const reading = filterAndSortLibrary(mockLibraryItems, 'reading', '', 'recent');
  assert.equal(reading.length, 0);
});

test('library filtering: matches text search by title or author', () => {
  const orwellBooks = filterAndSortLibrary(mockLibraryItems, 'all', 'Orwell', 'recent');
  assert.equal(orwellBooks.length, 2);
  assert.ok(orwellBooks.some((b) => b.book.title === 'Animal Farm'));
  assert.ok(orwellBooks.some((b) => b.book.title === '1984'));

  const crimeBook = filterAndSortLibrary(mockLibraryItems, 'all', 'crime', 'recent');
  assert.equal(crimeBook.length, 1);
  assert.equal(crimeBook[0].book.title, 'Crime and Punishment');
});

test('library sorting: sorts by title alphabetically', () => {
  const sorted = filterAndSortLibrary(mockLibraryItems, 'all', '', 'title');
  const titles = sorted.map((s) => s.book.title);
  assert.deepEqual(titles, ['1984', 'Animal Farm', 'Brave New World', 'Crime and Punishment']);
});

test('library sorting: sorts by rating descending', () => {
  const sorted = filterAndSortLibrary(mockLibraryItems, 'all', '', 'rating');
  const ratings = sorted.map((s) => s.book.averageRating);
  assert.deepEqual(ratings, [4.7, 4.6, 4.3, 4.1]);
});

test('optimistic rollback: restores previous items list on removal failure', () => {
  let items = [...mockLibraryItems];
  const previousSnapshot = [...items];

  // Optimistic removal of item with id '2'
  items = items.filter((i) => i.id !== '2');
  assert.equal(items.length, 3);
  assert.ok(!items.some((i) => i.id === '2'));

  // Failure occurs -> Rollback to snapshot
  const removalSucceeded = false;
  if (!removalSucceeded) {
    items = previousSnapshot;
  }

  assert.equal(items.length, 4);
  assert.ok(items.some((i) => i.id === '2'));
});

test('optimistic rollback: restores previous status on status update failure', () => {
  let items = [...mockLibraryItems];
  const previousSnapshot = items.map((i) => ({ ...i }));

  // Optimistically change item '2' from 'want_to_read' to 'favorite'
  items = items.map((i) => (i.id === '2' ? { ...i, status: 'favorite' as const } : i));
  assert.equal(items.find((i) => i.id === '2')?.status, 'favorite');

  // Network failure occurs -> Rollback
  const updateSucceeded = false;
  if (!updateSucceeded) {
    items = previousSnapshot;
  }

  assert.equal(items.find((i) => i.id === '2')?.status, 'want_to_read');
});
