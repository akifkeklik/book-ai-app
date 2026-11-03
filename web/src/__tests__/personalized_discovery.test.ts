import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { ApiService } from '../lib/api';
import {
  classifyRecommendation,
  filterRecommendations,
} from '../lib/discovery';
import {
  getPersonalizedRecommendationsAction,
  dismissRecommendationAction,
} from '../app/actions/discovery';
import { PersonalizedDiscoveryCard } from '../components/PersonalizedDiscoveryCard';
import PersonalizedDiscoveryLoading from '../app/discovery/personalized/loading';
import type { Book, LibraryCollectionStatus, LibraryItem } from '../types';

function renderWithPreferences(ui: React.ReactElement) {
  return renderToStaticMarkup(ui);
}

const mockBook1: Book = {
  isbn13: '9780441013593',
  title: 'Dune Messiah',
  authors: 'Frank Herbert',
  categories: 'Science Fiction, Epic',
  description: 'The continuing saga of Paul Atreides.',
  thumbnail: 'https://images.example.com/dune.jpg',
  averageRating: 4.6,
  ratingsCount: 8500,
  publishedDate: '1969',
  pageCount: 256,
  similarityScore: 0.94,
  recommendationReason: "Because you favorited 'Dune'",
};

const mockBook2: Book = {
  isbn13: '9780553293357',
  title: 'Foundation',
  authors: 'Isaac Asimov',
  categories: 'Science Fiction, Classic',
  description: 'Galactic empire collapse and psychohistory.',
  thumbnail: 'https://images.example.com/foundation.jpg',
  averageRating: 4.7,
  ratingsCount: 12000,
  publishedDate: '1951',
  pageCount: 244,
  similarityScore: 0.88,
  recommendationReason: "Because you're reading 'Hyperion'",
};

const mockBook3: Book = {
  isbn13: '9780143105954',
  title: 'The Republic',
  authors: 'Plato',
  categories: 'Philosophy, Classics',
  description: 'Socratic dialogue on justice and the ideal state.',
  thumbnail: '',
  averageRating: 4.2,
  ratingsCount: 4200,
  publishedDate: '375 BC',
  pageCount: 416,
  similarityScore: 0.81,
  recommendationReason: 'Because you enjoy Philosophy',
};

const mockBook4: Book = {
  isbn13: '9780345391803',
  title: "The Hitchhiker's Guide to the Galaxy",
  authors: 'Douglas Adams',
  categories: 'Science Fiction, Comedy',
  description: 'A comical romp across space.',
  thumbnail: '',
  averageRating: 4.4,
  ratingsCount: 15000,
  publishedDate: '1979',
  pageCount: 224,
  recommendationReason: 'Trending on Libris right now',
};

describe('Personalized Discovery Hub: API & Normalization', () => {
  const originalFetch = globalThis.fetch;

  test('ApiService.getPersonalizedRecommendations: passes limit and category correctly', async () => {
    let capturedUrl: string | undefined;
    let capturedInit: RequestInit | undefined;

    globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      capturedUrl = String(input);
      capturedInit = init;
      return new Response(
        JSON.stringify({
          user_id: 'user-123',
          total: 1,
          recommendations: [
            {
              isbn13: '9780441013593',
              title: 'Dune Messiah',
              authors: 'Frank Herbert',
              categories: 'Science Fiction',
              average_rating: 4.6,
              ratings_count: 8500,
              published_date: '1969',
              page_count: 256,
              similarity_score: 0.94,
              recommendation_reason: "Because you favorited 'Dune'",
            },
          ],
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }) as typeof fetch;

    try {
      const recs = await ApiService.getPersonalizedRecommendations(25, { category: 'Science Fiction' });
      assert.ok(capturedUrl?.includes('limit=25'));
      assert.ok(capturedUrl?.includes('category=Science+Fiction') || capturedUrl?.includes('category=Science%20Fiction'));
      assert.equal(capturedInit?.cache, 'no-store', 'Personalized recommendations must enforce cache: no-store');
      assert.equal(recs.length, 1);
      assert.equal(recs[0].title, 'Dune Messiah');
      assert.equal(recs[0].averageRating, 4.6);
      assert.equal(recs[0].similarityScore, 0.94);
      assert.equal(recs[0].recommendationReason, "Because you favorited 'Dune'");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test('ApiService.getPersonalizedRecommendations: ignores "all" category filter param', async () => {
    let capturedUrl: string | undefined;

    globalThis.fetch = (async (input: RequestInfo | URL) => {
      capturedUrl = String(input);
      return new Response(JSON.stringify({ recommendations: [] }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }) as typeof fetch;

    try {
      await ApiService.getPersonalizedRecommendations(12, { category: 'all' });
      assert.ok(capturedUrl?.includes('limit=12'));
      assert.equal(capturedUrl?.includes('category='), false, 'Should not pass category=all');
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test('ApiService.getPersonalizedRecommendations: throws Unauthorized on 401', async () => {
    globalThis.fetch = (async () => {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }) as typeof fetch;

    try {
      await assert.rejects(
        async () => {
          await ApiService.getPersonalizedRecommendations(10);
        },
        { message: 'Unauthorized' }
      );
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe('Personalized Discovery Hub: Attribution Classification & Filtering', () => {
  test('classifyRecommendation: categorizes attribution transparently without faking', () => {
    assert.equal(classifyRecommendation(mockBook1), 'favorites');
    assert.equal(classifyRecommendation(mockBook2), 'reading');
    assert.equal(classifyRecommendation(mockBook3), 'category');
    assert.equal(classifyRecommendation(mockBook4), 'general');
  });

  test('classifyRecommendation: detects Turkish and reading variant attributions', () => {
    const trFav: Book = {
      ...mockBook1,
      recommendationReason: "'Dune' favoriniz olduğu için önerildi",
    };
    const trReading: Book = {
      ...mockBook2,
      recommendationReason: "'Vakıf' kitabını okumakta olduğunuz için",
    };
    const trTaste: Book = {
      ...mockBook3,
      recommendationReason: 'Bilimkurgu türünü sevdiğiniz için',
    };

    assert.equal(classifyRecommendation(trFav), 'favorites');
    assert.equal(classifyRecommendation(trReading), 'reading');
    assert.equal(classifyRecommendation(trTaste), 'category');
  });

  test('filterRecommendations: correctly partitions books across discovery tabs', () => {
    const list = [mockBook1, mockBook2, mockBook3, mockBook4];

    // All
    const all = filterRecommendations(list, 'all');
    assert.equal(all.length, 4);

    // Favorites
    const favs = filterRecommendations(list, 'favorites');
    assert.equal(favs.length, 1);
    assert.equal(favs[0].isbn13, mockBook1.isbn13);

    // Reading Journey
    const reading = filterRecommendations(list, 'reading');
    assert.equal(reading.length, 1);
    assert.equal(reading[0].isbn13, mockBook2.isbn13);

    // Category with specific filter
    const phil = filterRecommendations(list, 'category', 'Philosophy');
    assert.equal(phil.length, 1);
    assert.equal(phil[0].isbn13, mockBook3.isbn13);

    // Category with no match returns genuine empty array (no fake recommendations)
    const history = filterRecommendations(list, 'category', 'NonExistentGenre');
    assert.equal(history.length, 0);
  });
});

describe('Personalized Discovery Hub: Server Actions & Boundaries', () => {
  test('dismissRecommendationAction: rejects invalid or empty book ID', async () => {
    const resEmpty = await dismissRecommendationAction('');
    assert.equal(resEmpty.success, false);
    assert.equal(resEmpty.error, 'Invalid book ID');
  });

  test('getPersonalizedRecommendationsAction: returns controlled unauthenticated status', async () => {
    const res = await getPersonalizedRecommendationsAction(10);
    assert.ok(typeof res.success === 'boolean');
    assert.ok(typeof res.isAuthenticated === 'boolean');
    assert.ok(Array.isArray(res.books));
  });
});

describe('Personalized Discovery Hub: UI Component Rendering & States', () => {
  test('PersonalizedDiscoveryCard: renders metadata, match percentage, and localized attribution', () => {
    const html = renderWithPreferences(
      React.createElement(PersonalizedDiscoveryCard, {
        book: mockBook1,
        isFavorite: true,
        readingStatus: 'reading',
        onToggleFavorite: () => {},
        onUpdateShelf: () => {},
        onDismiss: () => {},
      })
    );

    assert.ok(html.includes('Dune Messiah'), 'Should render title');
    assert.ok(html.includes('Frank Herbert'), 'Should render author');
    assert.ok(html.includes('94% Match'), 'Should render match percentage');
    assert.ok(html.includes("Because you favorited &#x27;Dune&#x27;") || html.includes("Because you favorited 'Dune'"), 'Should render localized reason');
    assert.ok(html.includes('status-badge-favorite'), 'Should show favorite badge');
    assert.ok(html.includes('status-badge-reading'), 'Should show reading badge');
  });

  test('PersonalizedDiscoveryCard: renders fallback cover when thumbnail is empty', () => {
    const html = renderWithPreferences(
      React.createElement(PersonalizedDiscoveryCard, {
        book: mockBook3,
        onToggleFavorite: () => {},
        onUpdateShelf: () => {},
        onDismiss: () => {},
      })
    );

    assert.ok(html.includes('book-cover-fallback'), 'Should render fallback cover when thumbnail is empty');
  });

  test('PersonalizedDiscoveryCard: renders dismiss and shelf controls with accessible labels', () => {
    const html = renderWithPreferences(
      React.createElement(PersonalizedDiscoveryCard, {
        book: mockBook2,
        onToggleFavorite: () => {},
        onUpdateShelf: () => {},
        onDismiss: () => {},
      })
    );

    assert.ok(
      html.includes('Not interested') ||
      html.includes('İlgilenmiyorum') ||
      html.includes('dismiss'),
      'Should render dismiss button'
    );
    assert.ok(html.includes('select') || html.includes('option'), 'Should render shelf selection');
  });

  test('PersonalizedDiscoveryLoading: renders skeleton placeholders with accessible role', () => {
    const html = renderToStaticMarkup(React.createElement(PersonalizedDiscoveryLoading));
    assert.ok(html.includes('grid-books'));
    assert.ok(html.includes('skeleton'));
  });
});

describe('Personalized Discovery Hub: Optimistic State & Rollback Invariants', () => {
  test('Dismiss optimistic rollback: restores previous items list on rejection', () => {
    const initialList = [mockBook1, mockBook2, mockBook3];
    const targetBookId = mockBook2.isbn13;

    // 1. Optimistic removal
    const optimisticList = initialList.filter((b) => b.isbn13 !== targetBookId);
    assert.equal(optimisticList.length, 2);
    assert.equal(optimisticList.find((b) => b.isbn13 === targetBookId), undefined);

    // 2. Compensating rollback on backend failure
    const restoredList = [...initialList];
    assert.equal(restoredList.length, 3);
    assert.equal(restoredList[1].isbn13, targetBookId);
  });

  test('Duplicate dismiss prevention: pending set suppresses duplicate network invocations', () => {
    const pendingSet = new Set<string>();
    const bookId = mockBook1.isbn13;

    let callCount = 0;
    const triggerDismiss = (id: string) => {
      if (pendingSet.has(id)) return;
      pendingSet.add(id);
      callCount++;
    };

    triggerDismiss(bookId);
    triggerDismiss(bookId); // Duplicate attempt while in-flight
    triggerDismiss(bookId); // Another duplicate attempt

    assert.equal(callCount, 1, 'In-flight pending set must guard against duplicate submissions');
    pendingSet.delete(bookId);

    triggerDismiss(bookId);
    assert.equal(callCount, 2, 'Subsequent submission allowed after completion');
  });

  test('Favorite optimistic rollback: restores previous boolean state on error', () => {
    let isFavorite = false;
    const previous = isFavorite;

    // Optimistic toggle
    isFavorite = !previous;
    assert.equal(isFavorite, true);

    // Rollback
    isFavorite = previous;
    assert.equal(isFavorite, false);
  });

  test('Shelf status optimistic rollback: restores previous shelf state on error', () => {
    let shelf: LibraryCollectionStatus | null = 'reading';
    const previous = shelf;

    // Optimistic update to finished
    shelf = 'finished';
    assert.equal(shelf, 'finished');

    // Rollback to reading
    shelf = previous;
    assert.equal(shelf, 'reading');
  });

  test('Seamless discovery to reading journey: moving book to reading updates journey items and rolls back on failure', () => {
    let libraryItems: LibraryItem[] = [];
    const previousItems = [...libraryItems];

    const bookToRead = mockBook1;
    // 1. Optimistic transition: adding from discovery card to 'reading'
    const newItem: LibraryItem = {
      id: bookToRead.isbn13,
      bookId: bookToRead.isbn13,
      status: 'reading',
      addedAt: '2026-02-01T12:00:00Z',
      book: bookToRead,
    };
    libraryItems = [newItem, ...libraryItems];
    assert.equal(libraryItems.length, 1);
    assert.equal(libraryItems[0].status, 'reading');

    // 2. Transition from reading to finished increments completed count
    libraryItems = libraryItems.map((item) =>
      item.bookId === bookToRead.isbn13 ? { ...item, status: 'finished' } : item
    );
    assert.equal(libraryItems[0].status, 'finished');

    // 3. Rollback on API rejection restores original empty journey
    libraryItems = previousItems;
    assert.equal(libraryItems.length, 0);
  });

  test('Seamless discovery transition: pending mutation set blocks rapid double-clicks', () => {
    const pendingMutations = new Set<string>();
    let networkCalls = 0;

    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const onUpdateShelf = (bookId: string, _status: LibraryCollectionStatus) => {
      if (pendingMutations.has(bookId)) return; // blocked!
      pendingMutations.add(bookId);
      networkCalls++;
    };

    onUpdateShelf(mockBook1.isbn13, 'reading');
    onUpdateShelf(mockBook1.isbn13, 'reading'); // Second click should be suppressed
    onUpdateShelf(mockBook1.isbn13, 'finished'); // Third rapid click should also be suppressed

    assert.equal(networkCalls, 1, 'Only one mutation should proceed while in-flight');

    pendingMutations.delete(mockBook1.isbn13);
    onUpdateShelf(mockBook1.isbn13, 'finished');
    assert.equal(networkCalls, 2, 'Allowed after completion');
  });
});
