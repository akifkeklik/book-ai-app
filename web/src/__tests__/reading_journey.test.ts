import test from 'node:test';
import assert from 'node:assert/strict';
import type { Book, LibraryItem } from '../types';
import {
  calculateReadingJourney,
  determineNextBook,
  type ReadingGoal,
} from '../lib/reading_journey';

const mockBook = (id: string, title: string, pageCount?: number, category: string = 'Fiction'): Book => ({
  isbn13: id,
  title,
  authors: 'Author ' + id,
  categories: category,
  description: '',
  thumbnail: '',
  averageRating: 4.5,
  ratingsCount: 10,
  publishedDate: '2024',
  pageCount: pageCount ?? 0,
});

test('Reading Journey: empty library has 0 progress and default safe goal', () => {
  const result = calculateReadingJourney([], 25);
  assert.equal(result.completedCount, 0);
  assert.equal(result.progressPercent, 0);
  assert.equal(result.isGoalReached, false);
  assert.equal(result.safeGoal, 25);
  assert.equal(result.readingCount, 0);
  assert.equal(result.wantToReadCount, 0);
});

test('Reading Journey: goal invalid, zero or negative falls back safely to default 20', () => {
  const resultZero = calculateReadingJourney([], 0);
  assert.equal(resultZero.safeGoal, 20);

  const resultNegative = calculateReadingJourney([], -10);
  assert.equal(resultNegative.safeGoal, 20);

  const resultNaN = calculateReadingJourney([], NaN);
  assert.equal(resultNaN.safeGoal, 20);
});

test('Reading Journey: derives completed count strictly from status === "finished", ignoring favorites', () => {
  const items: LibraryItem[] = [
    { id: '1', bookId: '1', status: 'finished', addedAt: '2026-01-01', book: mockBook('1', 'Book 1', 300) },
    { id: '2', bookId: '2', status: 'finished', addedAt: '2026-01-02', book: mockBook('2', 'Book 2', 250) },
    { id: '3', bookId: '3', status: 'favorite', isFavorite: true, addedAt: '2026-01-03', book: mockBook('3', 'Book 3', 400) },
    { id: '4', bookId: '4', status: 'reading', addedAt: '2026-01-04', book: mockBook('4', 'Book 4', 500) },
    { id: '5', bookId: '5', status: 'want_to_read', addedAt: '2026-01-05', book: mockBook('5', 'Book 5', 200) },
  ];

  const result = calculateReadingJourney(items, 10);
  assert.equal(result.completedCount, 2);
  assert.equal(result.favoriteCount, 1);
  assert.equal(result.readingCount, 1);
  assert.equal(result.wantToReadCount, 1);
  assert.equal(result.progressPercent, 20); // 2 / 10 = 20%
  assert.equal(result.isGoalReached, false);
});

test('Reading Journey: progress percentage clamps at 100% when goal exceeded', () => {
  const items: LibraryItem[] = [
    { id: '1', bookId: '1', status: 'finished', addedAt: '2026-01-01', book: mockBook('1', 'Book 1') },
    { id: '2', bookId: '2', status: 'finished', addedAt: '2026-01-02', book: mockBook('2', 'Book 2') },
    { id: '3', bookId: '3', status: 'finished', addedAt: '2026-01-03', book: mockBook('3', 'Book 3') },
  ];

  const result = calculateReadingJourney(items, 2);
  assert.equal(result.completedCount, 3);
  assert.equal(result.progressPercent, 100);
  assert.equal(result.isGoalReached, true);
});

test('Reading Journey: supports weekly reading goal calculation with safe defaults', () => {
  const items: LibraryItem[] = [
    { id: '1', bookId: '1', status: 'finished', addedAt: '2026-01-01', book: mockBook('1', 'Book 1') },
  ];

  const weeklyGoal: ReadingGoal = { type: 'weekly', target: 2 };
  const result = calculateReadingJourney(items, weeklyGoal);
  assert.equal(result.safeGoal, 2);
  assert.equal(result.completedCount, 1);
  assert.equal(result.progressPercent, 50);
  assert.equal(result.isGoalReached, false);

  // Invalid weekly target defaults safely to 1
  const invalidWeekly: ReadingGoal = { type: 'weekly', target: 0 };
  const invalidResult = calculateReadingJourney(items, invalidWeekly);
  assert.equal(invalidResult.safeGoal, 1);
  assert.equal(invalidResult.progressPercent, 100);
  assert.equal(invalidResult.isGoalReached, true);
});

test('Reading Journey: supports category/topic area reading goal', () => {
  const items: LibraryItem[] = [
    { id: '1', bookId: '1', status: 'finished', addedAt: '2026-01-01', book: mockBook('1', 'Sci-Fi 1', 300, 'Science Fiction') },
    { id: '2', bookId: '2', status: 'finished', addedAt: '2026-01-02', book: mockBook('2', 'Fiction 1', 250, 'Historical Fiction') },
    { id: '3', bookId: '3', status: 'finished', addedAt: '2026-01-03', book: mockBook('3', 'Sci-Fi 2', 400, 'Science Fiction') },
    { id: '4', bookId: '4', status: 'finished', addedAt: '2026-01-04', book: mockBook('4', 'Cookbook', 150, 'Cooking') },
  ];

  const categoryGoal: ReadingGoal = {
    type: 'category',
    target: 4,
    category: 'Science Fiction',
  };

  const result = calculateReadingJourney(items, categoryGoal);
  // Only the 2 Science Fiction books count toward this category goal
  assert.equal(result.completedCount, 2);
  assert.equal(result.safeGoal, 4);
  assert.equal(result.progressPercent, 50); // 2 / 4 = 50%
  assert.equal(result.isGoalReached, false);
});

test('Reading Journey: safely handles missing, zero or invalid page counts without division by zero', () => {
  const items: LibraryItem[] = [
    {
      id: '1',
      bookId: '1',
      status: 'reading',
      currentPage: 50,
      addedAt: '2026-01-01',
      book: mockBook('1', 'Book Without Total Pages', undefined),
    },
    {
      id: '2',
      bookId: '2',
      status: 'reading',
      currentPage: 0,
      addedAt: '2026-01-01',
      book: mockBook('2', 'Book With Zero Pages', 0),
    },
    {
      id: '3',
      bookId: '3',
      status: 'reading',
      currentPage: 75,
      addedAt: '2026-01-01',
      book: mockBook('3', 'Book With 150 Pages', 150),
    },
  ];

  const result = calculateReadingJourney(items, 20);
  assert.equal(result.readingProgress.length, 3);
  
  // Book 1: missing page count
  assert.equal(result.readingProgress[0].totalPages, null);
  assert.equal(result.readingProgress[0].percent, null);

  // Book 2: zero page count
  assert.equal(result.readingProgress[1].totalPages, null);
  assert.equal(result.readingProgress[1].percent, null);

  // Book 3: 75 / 150 = 50%
  assert.equal(result.readingProgress[2].totalPages, 150);
  assert.equal(result.readingProgress[2].percent, 50);
});

test('Reading Journey: determineNextBook prioritizes want_to_read candidates in recommendations', () => {
  const rec1 = mockBook('rec-1', 'Rec Book 1');
  const rec2 = mockBook('rec-2', 'Rec Book 2 (In Want To Read)');
  const rec3 = mockBook('rec-3', 'Rec Book 3');

  const libraryItems: LibraryItem[] = [
    { id: 'rec-2', bookId: 'rec-2', status: 'want_to_read', addedAt: '2026-01-01', book: rec2 },
  ];

  const nextBook = determineNextBook([rec1, rec2, rec3], libraryItems);
  assert.ok(nextBook);
  assert.equal(nextBook.isbn13, 'rec-2');
});

test('Reading Journey: determineNextBook excludes books already being read or completed', () => {
  const rec1 = mockBook('active-1', 'Already Reading');
  const rec2 = mockBook('finished-2', 'Already Finished');
  const rec3 = mockBook('fresh-3', 'Fresh Recommendation');

  const libraryItems: LibraryItem[] = [
    { id: 'active-1', bookId: 'active-1', status: 'reading', addedAt: '2026-01-01', book: rec1 },
    { id: 'finished-2', bookId: 'finished-2', status: 'finished', addedAt: '2026-01-02', book: rec2 },
  ];

  const nextBook = determineNextBook([rec1, rec2, rec3], libraryItems);
  assert.ok(nextBook);
  assert.equal(nextBook.isbn13, 'fresh-3');
});
