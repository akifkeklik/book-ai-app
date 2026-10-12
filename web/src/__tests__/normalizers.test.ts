import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeBook, normalizeBooks } from '../lib/normalizers';

test('normalizeBook: correctly maps backend snake_case DTO fields to camelCase', () => {
  const backendDto = {
    isbn13: '9780143127741',
    title: 'The Great Gatsby',
    authors: 'F. Scott Fitzgerald',
    categories: 'Fiction, Classics',
    description: 'A classic novel of the Jazz Age.',
    thumbnail: 'https://example.com/gatsby.jpg',
    average_rating: 4.25,
    ratings_count: 1250,
    published_date: '1925-04-10',
    page_count: 180,
    similarity_score: 0.88,
    recommendation_reason: 'Because you love American classics',
    explanation: 'Captures the disillusionment of the roaring twenties.',
    explanation_source_book: 'Tender is the Night',
  };

  const book = normalizeBook(backendDto);

  assert.equal(book.isbn13, '9780143127741');
  assert.equal(book.title, 'The Great Gatsby');
  assert.equal(book.authors, 'F. Scott Fitzgerald');
  assert.equal(book.categories, 'Fiction, Classics');
  assert.equal(book.description, 'A classic novel of the Jazz Age.');
  assert.equal(book.thumbnail, 'https://example.com/gatsby.jpg');
  assert.equal(book.averageRating, 4.25);
  assert.equal(book.ratingsCount, 1250);
  assert.equal(book.publishedDate, '1925-04-10');
  assert.equal(book.pageCount, 180);
  assert.equal(book.similarityScore, 0.88);
  assert.equal(book.recommendationReason, 'Because you love American classics');
  assert.equal(book.explanation, 'Captures the disillusionment of the roaring twenties.');
  assert.equal(book.explanationSourceBook, 'Tender is the Night');
});

test('normalizeBook: preserves existing camelCase fields', () => {
  const camelCaseInput = {
    isbn13: '9780441013593',
    title: 'Dune',
    authors: 'Frank Herbert',
    categories: 'Sci-Fi',
    description: 'Spice and sand',
    thumbnail: 'https://example.com/dune.jpg',
    averageRating: 4.7,
    ratingsCount: 89000,
    publishedDate: '1965',
    pageCount: 688,
    similarityScore: 0.95,
    recommendationReason: 'Epic Sci-Fi worldbuilding',
    explanation: 'Deep lore and political intrigue',
    explanationSourceBook: 'Foundation',
  };

  const book = normalizeBook(camelCaseInput);

  assert.equal(book.averageRating, 4.7);
  assert.equal(book.ratingsCount, 89000);
  assert.equal(book.publishedDate, '1965');
  assert.equal(book.pageCount, 688);
  assert.equal(book.similarityScore, 0.95);
  assert.equal(book.recommendationReason, 'Epic Sci-Fi worldbuilding');
  assert.equal(book.explanationSourceBook, 'Foundation');
});

test('normalizeBook: preserves numeric 0 without discarding it via truthiness checks', () => {
  const zeroDto = {
    isbn13: '9780000000000',
    title: 'Brand New Book',
    authors: 'New Author',
    average_rating: 0,
    ratings_count: 0,
    page_count: 0,
    similarity_score: 0,
  };

  const book = normalizeBook(zeroDto);

  assert.strictEqual(book.averageRating, 0, 'averageRating should be numeric 0, not undefined or NaN');
  assert.strictEqual(book.ratingsCount, 0, 'ratingsCount should be numeric 0');
  assert.strictEqual(book.pageCount, 0, 'pageCount should be numeric 0');
  assert.strictEqual(book.similarityScore, 0, 'similarityScore should be numeric 0, not undefined');
});

test('normalizeBook: handles null, missing, and malformed optional fields safely', () => {
  const sparseDto = {
    isbn13: null,
    isbn: '1234567890',
    title: null,
    author: 'Solo Author',
    average_rating: null,
    ratings_count: undefined,
    published_date: null,
    page_count: 'not-a-number',
    similarity_score: null,
    recommendation_reason: null,
  };

  const book = normalizeBook(sparseDto);

  assert.equal(book.isbn13, '1234567890');
  assert.equal(book.title, 'Unknown Title');
  assert.equal(book.authors, 'Solo Author');
  assert.equal(book.averageRating, 0);
  assert.equal(book.ratingsCount, 0);
  assert.equal(book.publishedDate, '');
  assert.equal(book.pageCount, 0);
  assert.equal(book.similarityScore, undefined);
  assert.equal(book.recommendationReason, undefined);
});

test('normalizeBook: safely handles completely empty, null, or non-object input', () => {
  const fromNull = normalizeBook(null);
  assert.equal(fromNull.title, 'Unknown Title');
  assert.equal(fromNull.averageRating, 0);

  const fromUndefined = normalizeBook(undefined);
  assert.equal(fromUndefined.title, 'Unknown Title');

  const fromString = normalizeBook('invalid string');
  assert.equal(fromString.title, 'Unknown Title');
});

test('normalizeBooks: normalizes arrays and ignores invalid items', () => {
  const rawList = [
    { isbn13: '111', title: 'Book One', average_rating: 4.0 },
    null,
    undefined,
    'garbage',
    { isbn13: '222', title: 'Book Two', averageRating: 4.5 },
  ];

  const books = normalizeBooks(rawList);

  assert.equal(books.length, 2);
  assert.equal(books[0].isbn13, '111');
  assert.equal(books[0].averageRating, 4.0);
  assert.equal(books[1].isbn13, '222');
  assert.equal(books[1].averageRating, 4.5);

  assert.deepEqual(normalizeBooks(null), []);
  assert.deepEqual(normalizeBooks(undefined), []);
  assert.deepEqual(normalizeBooks('not-an-array'), []);
});
