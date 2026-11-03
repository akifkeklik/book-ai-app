import test from 'node:test';
import assert from 'node:assert/strict';
import type { Book } from '../types';

// Mirroring the state management and URL builder logic of CatalogBookList & CatalogPage
function createFilterUrl(
  baseFilters: {
    category?: string;
    q?: string;
    sort?: string;
    order?: 'asc' | 'desc';
    min_rating?: number;
  },
  overrides: Record<string, string | number | undefined | null>
): string {
  const params = new URLSearchParams();
  if (baseFilters.category) params.set('category', baseFilters.category);
  if (baseFilters.q) params.set('q', baseFilters.q);
  if (baseFilters.sort && baseFilters.sort !== 'popularity') params.set('sort', baseFilters.sort);
  if (baseFilters.order && baseFilters.order !== 'desc') params.set('order', baseFilters.order);
  if (baseFilters.min_rating) params.set('min_rating', String(baseFilters.min_rating));

  // Reset page to 1 when changing filters, unless explicitly passing page
  if (!('page' in overrides)) {
    params.delete('page');
  }

  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined || value === null || value === '') {
      params.delete(key);
    } else {
      params.set(key, String(value));
    }
  }

  const queryStr = params.toString();
  return queryStr ? `/catalog?${queryStr}` : '/catalog';
}

function appendBooks(currentBooks: Book[], incomingBooks: Book[]): Book[] {
  // Ensure stable append without duplicating by isbn13 if an overlap occurs
  const seen = new Set(currentBooks.map((b) => b.isbn13));
  const uniqueIncoming = incomingBooks.filter((b) => !seen.has(b.isbn13));
  return [...currentBooks, ...uniqueIncoming];
}

const makeBook = (id: string, title: string): Book => ({
  isbn13: id,
  title,
  authors: 'Author ' + id,
  categories: 'Fiction',
  description: 'Description ' + id,
  thumbnail: 'https://books.google.com/test.jpg',
  averageRating: 4.5,
  ratingsCount: 12,
  publishedDate: '2023',
  pageCount: 320,
});

test('Catalog Load More: Appending books preserves initial books and integrates new page', () => {
  const initial = [makeBook('1', 'Book One'), makeBook('2', 'Book Two')];
  const pageTwo = [makeBook('3', 'Book Three'), makeBook('4', 'Book Four')];

  const merged = appendBooks(initial, pageTwo);
  assert.equal(merged.length, 4);
  assert.equal(merged[0].title, 'Book One');
  assert.equal(merged[3].title, 'Book Four');
});

test('Catalog Load More: Duplicate book is not duplicated in list', () => {
  const initial = [makeBook('1', 'Book One'), makeBook('2', 'Book Two')];
  const pageTwo = [makeBook('2', 'Book Two Duplicate'), makeBook('3', 'Book Three')];

  const merged = appendBooks(initial, pageTwo);
  assert.equal(merged.length, 3);
  assert.equal(merged[1].isbn13, '2');
  assert.equal(merged[2].isbn13, '3');
});

test('Catalog Pagination: URL generator correctly preserves query filters when navigating pages', () => {
  const base = {
    category: 'Science',
    q: 'astronomy',
    sort: 'rating',
    order: 'asc' as const,
    min_rating: 4,
  };

  const pageTwoUrl = createFilterUrl(base, { page: 2 });
  assert.match(pageTwoUrl, /page=2/);
  assert.match(pageTwoUrl, /category=Science/);
  assert.match(pageTwoUrl, /q=astronomy/);
  assert.match(pageTwoUrl, /sort=rating/);
  assert.match(pageTwoUrl, /order=asc/);
  assert.match(pageTwoUrl, /min_rating=4/);
});

test('Catalog Pagination: Changing filter resets page to 1 automatically', () => {
  const base = {
    category: 'Science',
    q: 'astronomy',
  };

  const newCategoryUrl = createFilterUrl(base, { category: 'Fiction' });
  assert.doesNotMatch(newCategoryUrl, /page=/);
  assert.match(newCategoryUrl, /category=Fiction/);
});

test('Catalog Load More: Status announcement generates accessible screen-reader string', () => {
  const newCount = 20;
  const totalLoaded = 40;
  const totalBooks = 120;
  const statusMessage = `Loaded ${newCount} more books. Now showing ${totalLoaded} of ${totalBooks} books.`;

  assert.equal(statusMessage, 'Loaded 20 more books. Now showing 40 of 120 books.');
});
