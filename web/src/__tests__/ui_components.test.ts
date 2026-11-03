import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import { Skeleton, BookCardSkeleton, BookGridSkeleton, BookDetailSkeleton } from '../components/Skeleton';
import { BookCard } from '../components/BookCard';
import type { Book } from '../types';

describe('UI Acceleration & Skeleton Components', () => {
  test('Skeleton renders with custom width, height, and borderRadius', () => {
    const el = Skeleton({ width: '200px', height: '40px', borderRadius: '16px' });
    assert.ok(el, 'Skeleton element should be rendered');
    assert.equal(el.type, 'div');
    assert.equal(el.props.className, 'skeleton');
    assert.equal(el.props.style.width, '200px');
    assert.equal(el.props.style.height, '40px');
    assert.equal(el.props.style.borderRadius, '16px');
    assert.equal(el.props['aria-hidden'], 'true');
  });

  test('BookCardSkeleton renders cover, title, author, and rating placeholders', () => {
    const el = BookCardSkeleton();
    assert.ok(el, 'BookCardSkeleton should render');
    assert.ok(el.props.className.includes('book-card-skeleton'));
    const children = el.props.children;
    assert.equal(children.length, 4, 'Should have 4 placeholder elements');
    assert.ok(children[0].props.className.includes('cover-skeleton'));
    assert.ok(children[1].props.className.includes('title-skeleton'));
    assert.ok(children[2].props.className.includes('author-skeleton'));
    assert.ok(children[3].props.className.includes('rating-skeleton'));
  });

  test('BookGridSkeleton renders requested number of book card skeletons', () => {
    const el = BookGridSkeleton({ count: 6 });
    assert.ok(el, 'BookGridSkeleton should render');
    assert.equal(el.props.className, 'grid-books');
    assert.equal(el.props.role, 'status');
    assert.equal(el.props.children.length, 6, 'Should render exactly 6 skeleton cards');
  });

  test('BookDetailSkeleton renders 2-column editorial structure with status role', () => {
    const el = BookDetailSkeleton();
    assert.ok(el, 'BookDetailSkeleton should render');
    assert.equal(el.props.role, 'status');
    assert.equal(el.props['aria-label'], 'Loading book details...');
  });

  test('BookCard renders accessible label and var(--rating) token', async () => {
    const { renderToStaticMarkup } = await import('react-dom/server');

    const mockBook: Book = {
      isbn13: '9780141439518',
      title: 'Pride and Prejudice',
      authors: 'Jane Austen',
      categories: 'Classic, Romance',
      thumbnail: 'https://books.google.com/test.jpg',
      description: 'A classic story.',
      publishedDate: '1813',
      pageCount: 432,
      averageRating: 4.8,
      ratingsCount: 1500,
      similarityScore: 0.94,
      recommendationReason: 'Because you love Regency classics',
    };

    const html = renderToStaticMarkup(React.createElement(BookCard, { book: mockBook }));
    assert.ok(html.includes('Pride and Prejudice'), 'Should include book title');
    assert.ok(html.includes('Jane Austen'), 'Should include author');
    assert.ok(html.includes('var(--rating)'), 'Should use var(--rating) token');
    assert.ok(html.includes('aria-label="Pride and Prejudice by Jane Austen"'), 'Should have accessible label');
    assert.ok(html.includes('94% Match'), 'Should display similarity score');
    assert.ok(html.includes('Because you love Regency classics'), 'Should display recommendation reason');
  });

  test('BookCard renders visually distinct status badges for favorite and reading shelf', async () => {
    const { renderToStaticMarkup } = await import('react-dom/server');

    const mockBook: Book = {
      isbn13: '9780141439518',
      title: 'Pride and Prejudice',
      authors: 'Jane Austen',
      categories: 'Classic',
      thumbnail: 'https://books.google.com/test.jpg',
      description: 'A classic story.',
      publishedDate: '1813',
      pageCount: 432,
      averageRating: 4.8,
      ratingsCount: 1500,
    };

    // Test favorite badge
    const favHtml = renderToStaticMarkup(
      React.createElement(BookCard, { book: mockBook, isFavorite: true })
    );
    assert.ok(favHtml.includes('status-badge-favorite'), 'Should include favorite badge class');
    assert.ok(favHtml.includes('Favorite'), 'Should display Favorite label');

    // Test reading status badge
    const readingHtml = renderToStaticMarkup(
      React.createElement(BookCard, { book: mockBook, userInteraction: 'reading' })
    );
    assert.ok(readingHtml.includes('status-badge-reading'), 'Should include reading badge class');
    assert.ok(readingHtml.includes('Reading'), 'Should display Reading label');

    // Test want to read status badge
    const wantHtml = renderToStaticMarkup(
      React.createElement(BookCard, { book: mockBook, userInteraction: 'want_to_read' })
    );
    assert.ok(wantHtml.includes('status-badge-want-to-read'), 'Should include want to read badge class');
    assert.ok(wantHtml.includes('Want to Read'), 'Should display Want to Read label');

    // Test finished status badge
    const finishedHtml = renderToStaticMarkup(
      React.createElement(BookCard, { book: mockBook, userInteraction: 'finished' })
    );
    assert.ok(finishedHtml.includes('status-badge-finished'), 'Should include finished badge class');
    assert.ok(finishedHtml.includes('Finished'), 'Should display Finished label');
  });

  test('Spotlight: searchCatalogAction safely handles empty and whitespace queries without network calls', async () => {
    const { searchCatalogAction } = await import('../app/actions/catalog');
    const emptyRes = await searchCatalogAction('');
    assert.equal(emptyRes.success, true);
    assert.deepEqual(emptyRes.books, []);

    const whitespaceRes = await searchCatalogAction('    ');
    assert.equal(whitespaceRes.success, true);
    assert.deepEqual(whitespaceRes.books, []);
  });

  test('Spotlight: searchCatalogAction queries ApiService with trimmed query and limit', async () => {
    const { searchCatalogAction } = await import('../app/actions/catalog');
    const { ApiService } = await import('../lib/api');
    const originalGetBooks = ApiService.getBooks;

    try {
      let capturedParams: Record<string, unknown> | undefined;
      ApiService.getBooks = async (params: Record<string, unknown>) => {
        capturedParams = params;
        return {
          books: [
            {
              isbn13: '9780451524935',
              title: '1984',
              authors: 'George Orwell',
              categories: 'Classics',
              description: 'A dystopian social science fiction novel.',
              thumbnail: '',
              averageRating: 4.7,
              ratingsCount: 2000,
              publishedDate: '1949',
              pageCount: 328,
            },
          ],
          total: 1,
          total_pages: 1,
        };
      };

      const res = await searchCatalogAction('   1984   ', 5);
      assert.equal(res.success, true);
      assert.equal(res.books.length, 1);
      assert.equal(res.books[0].title, '1984');
      assert.equal(capturedParams?.query, '1984');
      assert.equal(capturedParams?.per_page, 5);
    } finally {
      ApiService.getBooks = originalGetBooks;
    }
  });

  test('Spotlight: searchCatalogAction gracefully catches exceptions and returns error without throwing', async () => {
    const { searchCatalogAction } = await import('../app/actions/catalog');
    const { ApiService } = await import('../lib/api');
    const originalGetBooks = ApiService.getBooks;

    try {
      ApiService.getBooks = async () => {
        throw new Error('Catalog backend connection refused');
      };

      const res = await searchCatalogAction('sci-fi');
      assert.equal(res.success, false);
      assert.deepEqual(res.books, []);
      assert.ok(res.error?.includes('Catalog backend connection refused'));
    } finally {
      ApiService.getBooks = originalGetBooks;
    }
  });
});

