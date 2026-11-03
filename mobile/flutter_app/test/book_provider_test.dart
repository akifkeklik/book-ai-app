import 'package:flutter_test/flutter_test.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/providers/catalog_provider.dart';
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/application/use_cases/manage_catalog_use_case.dart';
import 'package:book_ai_app/application/use_cases/manage_recommendations_use_case.dart';

// ---------------------------------------------------------------------------
// Fake BookRepository — no network, no Hive, no Supabase
// ---------------------------------------------------------------------------
class FakeBookRepository implements BookRepository {
  // Configurable behaviour
  List<Book> popularBooksResult = [];
  Exception? popularBooksError;

  List<Book> personalizedResult = [];
  Exception? personalizedError;

  List<String> categoriesResult = [];

  int totalCount = 0;
  List<Book> cachedBooks = [];
  List<Book> savedToCache = [];

  int getPopularCallCount = 0;

  // Helper to build a minimal Book
  static Book book(String isbn, String title) => Book(
        isbn13: isbn,
        title: title,
        authors: 'Author',
        description: '',
        categories: '',
        thumbnail: '',
        averageRating: 0,
        ratingsCount: 0,
        publishedDate: '2020-01-01',
        pageCount: 100,
      );

  @override
  Future<List<Book>> getPopularBooks({int limit = 20}) async {
    getPopularCallCount++;
    if (popularBooksError != null) throw popularBooksError!;
    return popularBooksResult;
  }

  List<Book> morePopularBooksResult = [];

  @override
  Future<List<Book>> getMorePopularBooks(
          {required int offset, int limit = 20}) async =>
      morePopularBooksResult;

  @override
  Future<List<Book>> getPersonalizedRecommendations(String userId) async {
    if (personalizedError != null) throw personalizedError!;
    return personalizedResult;
  }

  Exception? fallbackError;

  @override
  Future<List<Book>> getFallbackRecommendations(String userId) async {
    if (fallbackError != null) throw fallbackError!;
    return personalizedResult;
  }

  @override
  Future<List<Book>> searchBooks(String query) async => [];

  @override
  Future<List<Map<String, dynamic>>> getCategories() async => [];

  @override
  Future<bool> submitFeedback(
          {required String userId,
          required String bookId,
          required String interaction}) async =>
      true;

  @override
  Future<bool> submitOnboarding(
          {required String userId,
          required List<String> bookIds,
          required List<String> genres}) async =>
      true;

  @override
  Future<Map<String, dynamic>> getBooksByCategory({
    required String category,
    int page = 1,
    int perPage = 40,
    String? sort,
    String? author,
    String? publisher,
    int? minPages,
    int? maxPages,
    double? minRating,
    int? publishedFrom,
    int? publishedTo,
  }) async =>
      {};

  Map<String, dynamic> chatWithAIResult = {};
  Exception? chatError;
  int chatCallCount = 0;
  Duration? chatDelay;

  @override
  Future<Map<String, dynamic>> chatWithAI(String query) async {
    chatCallCount++;
    if (chatDelay != null) await Future.delayed(chatDelay!);
    if (chatError != null) throw chatError!;
    return chatWithAIResult;
  }

  @override
  Future<List<Book>> getRecommendations(String title) async => [];

  @override
  Future<void> trackActivity(
      {required String userId,
      required String activityType,
      required String bookId}) async {}

  @override
  Future<Book?> getBookByIsbn(String isbn) async => null;

  @override
  Future<String?> getUserInteraction(String userId, String bookId) async => null;

  @override
  Future<void> upsertUserProfile(
      {required String userId,
      required List<String> preferredGenres,
      required int readingFrequency,
      required List<String> preferredAuthors,
      required String preferredVibe}) async {}

  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async => null;

  @override
  List<Book> getCachedPopularBooks() => cachedBooks;

  @override
  void savePopularBooksToCache(List<Book> books) => savedToCache = books;

  Map<String, List<Book>> cachedSearchResultsMap = {};
  Map<String, List<Book>> savedSearchResultsMap = {};

  @override
  List<Book> getCachedSearchResults(String query) =>
      cachedSearchResultsMap[query.trim().toLowerCase()] ?? [];

  @override
  void saveSearchResultsToCache(String query, List<Book> books) {
    savedSearchResultsMap[query.trim().toLowerCase()] = books;
  }

  Map<String, List<Book>> cachedCategoryBooksMap = {};
  Map<String, List<Book>> savedCategoryBooksMap = {};

  @override
  List<Book> getCachedCategoryBooks(String category) =>
      cachedCategoryBooksMap[category.trim().toLowerCase()] ?? [];

  @override
  void saveCategoryBooksToCache(String category, List<Book> books,
      {int? total, int? totalPages}) {
    savedCategoryBooksMap[category.trim().toLowerCase()] = books;
  }

  @override
  Future<int> getTotalBookCount() async => totalCount;

  @override
  void clearUserCache(String userId) {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('CatalogProvider.fetchPopular', () {
    test('success: loading -> loaded, books populated', () async {
      final repo = FakeBookRepository();
      repo.popularBooksResult = [
        FakeBookRepository.book('111', 'Book A'),
        FakeBookRepository.book('222', 'Book B'),
      ];
      final provider = CatalogProvider(
        manageCatalog: ManageCatalogUseCase(repo),
      );

      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.loaded);
      expect(provider.popularBooks.length, 2);
      expect(provider.popularBooks.first.title, 'Book A');
      expect(provider.error, isNull);
      provider.dispose();
    });

    test('failure: loading -> error, error message set', () async {
      final repo = FakeBookRepository();
      repo.popularBooksError = Exception('network timeout');
      final provider = CatalogProvider(
        manageCatalog: ManageCatalogUseCase(repo),
      );

      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.error);
      expect(provider.error, isNotNull);
      expect(provider.error, contains('error_loading_books'));
      provider.dispose();
    });

    test('duplicate request prevention: second call while loading is ignored',
        () async {
      final repo = FakeBookRepository();
      repo.popularBooksResult = [];

      final provider = CatalogProvider(
        manageCatalog: ManageCatalogUseCase(repo),
      );
      await Future.delayed(Duration.zero);

      repo.getPopularCallCount = 0;
      final f1 = provider.fetchPopular(force: true);
      final f2 = provider.fetchPopular(force: true);
      await Future.wait([f1, f2]);

      expect(repo.getPopularCallCount, 1);
      provider.dispose();
    });

    test('state correctness: after success, status is loaded and books match',
        () async {
      final repo = FakeBookRepository();
      final expected = [
        FakeBookRepository.book('A1', 'Alpha'),
        FakeBookRepository.book('B2', 'Beta'),
        FakeBookRepository.book('C3', 'Gamma'),
      ];
      repo.popularBooksResult = expected;
      final provider = CatalogProvider(
        manageCatalog: ManageCatalogUseCase(repo),
      );

      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.loaded);
      expect(provider.popularBooks.map((b) => b.isbn13).toList(),
          containsAll(['A1', 'B2', 'C3']));
      provider.dispose();
    });

    test('retry after error: second fetchPopular succeeds', () async {
      final repo = FakeBookRepository();
      repo.popularBooksError = Exception('server error');
      final provider = CatalogProvider(
        manageCatalog: ManageCatalogUseCase(repo),
      );

      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);
      expect(provider.status, CatalogStatus.error);

      repo.popularBooksError = null;
      repo.popularBooksResult = [FakeBookRepository.book('X1', 'Recovered')];
      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.loaded);
      expect(provider.popularBooks.first.title, 'Recovered');
      provider.dispose();
    });
  });

  group(
      'RecommendationProvider.fetchPersonalizedRecs - stale response protection',
      () {
    test('stale userId response does not overwrite newer userId state',
        () async {
      final repo = FakeBookRepository();
      repo.personalizedResult = [FakeBookRepository.book('P1', 'PersonalBook')];
      final provider = RecommendationProvider(
        manageRecommendations: ManageRecommendationsUseCase(repo),
      );

      await Future.delayed(Duration.zero);

      await provider.fetchPersonalizedRecs('user-A', []);
      expect(provider.status, RecommendationStatus.loaded);
      expect(provider.personalizedRecs.first.isbn13, 'P1');

      repo.personalizedResult = [];
      await provider.fetchPersonalizedRecs('user-B', []);

      expect(provider.status, RecommendationStatus.loaded);
      expect(provider.personalizedRecs, isEmpty);
      provider.dispose();
    });

    test('personalized failure + fallback failure: status becomes error',
        () async {
      final repo = FakeBookRepository();
      repo.personalizedError = Exception('AI service down');
      repo.fallbackError = Exception('Fallback down');
      final provider = RecommendationProvider(
        manageRecommendations: ManageRecommendationsUseCase(repo),
      );

      await Future.delayed(Duration.zero);
      await provider.fetchPersonalizedRecs('user-1', []);

      expect(provider.status, RecommendationStatus.error);
      provider.dispose();
    });

    test('clearUserData: clears personalized recs and status', () async {
      final repo = FakeBookRepository();
      repo.personalizedResult = [
        const Book(
            isbn13: '1',
            title: 'Personalized 1',
            authors: 'Author',
            categories: '',
            description: '',
            thumbnail: '',
            averageRating: 0,
            ratingsCount: 0,
            publishedDate: '',
            pageCount: 0)
      ];

      final provider = RecommendationProvider(
        manageRecommendations: ManageRecommendationsUseCase(repo),
      );

      await provider.fetchPersonalizedRecs('userA', []);
      expect(provider.status, RecommendationStatus.loaded);
      expect(provider.personalizedRecs, isNotEmpty);

      provider.clearUserData();
      expect(provider.status, RecommendationStatus.initial);
      expect(provider.personalizedRecs, isEmpty);
    });

    test('submitFeedback dislike optimistically removes book and refreshes recs',
        () async {
      final repo = FakeBookRepository();
      repo.personalizedResult = [
        FakeBookRepository.book('B1', 'Book One'),
        FakeBookRepository.book('B2', 'Book Two'),
      ];

      final provider = RecommendationProvider(
        manageRecommendations: ManageRecommendationsUseCase(repo),
      );

      await provider.fetchPersonalizedRecs('userA', []);
      expect(provider.personalizedRecs.length, 2);

      // Submit dislike for B1 - should be optimistically removed
      repo.personalizedResult = [FakeBookRepository.book('B2', 'Book Two')];
      await provider.submitFeedback(
        userId: 'userA',
        bookId: 'B1',
        interaction: 'dislike',
      );

      expect(provider.personalizedRecs.any((b) => b.isbn13 == 'B1'), isFalse);
      expect(provider.personalizedRecs.length, 1);
      expect(provider.personalizedRecs.first.isbn13, 'B2');
    });

    test('submitFeedback favorite/like/want_to_read triggers recs refresh',
        () async {
      final repo = FakeBookRepository();
      repo.personalizedResult = [FakeBookRepository.book('B1', 'Initial Rec')];

      final provider = RecommendationProvider(
        manageRecommendations: ManageRecommendationsUseCase(repo),
      );

      await provider.fetchPersonalizedRecs('userA', []);
      expect(provider.personalizedRecs.first.title, 'Initial Rec');

      // Update backend returned recs
      repo.personalizedResult = [
        FakeBookRepository.book('B2', 'Updated Rec Based on Feedback')
      ];

      await provider.submitFeedback(
        userId: 'userA',
        bookId: 'B1',
        interaction: 'want_to_read',
      );

      expect(provider.personalizedRecs.first.title,
          'Updated Rec Based on Feedback');
    });
  });

  group('CatalogProvider - Filtering and State Correctness', () {
    late FakeBookRepository repo;
    late List<Book> testBooks;

    setUp(() {
      repo = FakeBookRepository();
      testBooks = [
        const Book(
          isbn13: '9780141439518',
          title: 'Pride and Prejudice',
          authors: 'Jane Austen',
          categories: 'Classic, Romance',
          description: 'A romantic novel of manners.',
          thumbnail: '',
          averageRating: 4.5,
          ratingsCount: 1000,
          publishedDate: '1813',
          pageCount: 279,
        ),
        const Book(
          isbn13: '9780061120084',
          title: 'To Kill a Mockingbird',
          authors: 'Harper Lee',
          categories: 'Classic, Fiction',
          description: 'A story of racial injustice and loss of innocence.',
          thumbnail: '',
          averageRating: 4.8,
          ratingsCount: 2000,
          publishedDate: '1960',
          pageCount: 336,
        ),
        const Book(
          isbn13: '9780451524935',
          title: '1984',
          authors: 'George Orwell',
          categories: 'Dystopian, Science Fiction',
          description: 'A totalitarian regime surveillance state.',
          thumbnail: '',
          averageRating: 4.2,
          ratingsCount: 1500,
          publishedDate: '1949',
          pageCount: 328,
        ),
        const Book(
          isbn13: '9780261103252',
          title: 'The Lord of the Rings',
          authors: 'J.R.R. Tolkien',
          categories: 'Fantasy, Adventure',
          description: 'An epic high-fantasy novel.',
          thumbnail: '',
          averageRating: 4.9,
          ratingsCount: 5000,
          publishedDate: '1954',
          pageCount: 1178,
        ),
        const Book(
          isbn13: '9780000000000',
          title: 'Unknown Pamphlet',
          authors: '',
          categories: '',
          description: '',
          thumbnail: '',
          averageRating: 0.0,
          ratingsCount: 0,
          publishedDate: '2020',
          pageCount: 0, // missing/zero pages
        ),
      ];
      repo.popularBooksResult = testBooks;
    });

    test('author filter filters correctly (case-insensitive substring)',
        () async {
      final provider =
          CatalogProvider(manageCatalog: ManageCatalogUseCase(repo));
      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      expect(provider.popularBooks.length, 5);

      provider.setFilters(author: 'austen');
      expect(provider.popularBooks.length, 1);
      expect(provider.popularBooks.first.title, 'Pride and Prejudice');

      // Partial author match
      provider.setFilters(author: 'orwell');
      expect(provider.popularBooks.length, 1);
      expect(provider.popularBooks.first.title, '1984');

      provider.dispose();
    });

    test(
        'page range filter: 1 (<300), 2 (300-500), 3 (>500) and excludes zero/missing pages',
        () async {
      final provider =
          CatalogProvider(manageCatalog: ManageCatalogUseCase(repo));
      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      // Range 1: <300 pages (Pride and Prejudice: 279, Unknown: 0 -> excluded)
      provider.setFilters(pageRange: 1);
      expect(provider.popularBooks.length, 1);
      expect(provider.popularBooks.first.title, 'Pride and Prejudice');

      // Range 2: 300-500 pages (Mockingbird: 336, 1984: 328)
      provider.setFilters(pageRange: 2);
      expect(provider.popularBooks.length, 2);
      expect(provider.popularBooks.map((b) => b.title),
          containsAll(['To Kill a Mockingbird', '1984']));

      // Range 3: >500 pages (LotR: 1178)
      provider.setFilters(pageRange: 3);
      expect(provider.popularBooks.length, 1);
      expect(provider.popularBooks.first.title, 'The Lord of the Rings');

      provider.dispose();
    });

    test('combined filters: author, category, and page range work in unison',
        () async {
      final provider =
          CatalogProvider(manageCatalog: ManageCatalogUseCase(repo));
      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      provider.setFilters(
        category: 'Classic',
        pageRange: 2, // 300-500
      );
      // Mockingbird (Classic, 336 pages) matches; Pride and Prejudice (279 pages) does not
      expect(provider.popularBooks.length, 1);
      expect(provider.popularBooks.first.title, 'To Kill a Mockingbird');

      // Non-matching combined filter results in empty list
      provider.setFilters(author: 'Tolkien');
      expect(provider.popularBooks, isEmpty);

      provider.dispose();
    });

    test('search query filter matches title, author, or description', () async {
      final provider =
          CatalogProvider(manageCatalog: ManageCatalogUseCase(repo));
      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      provider.setFilters(searchQuery: 'surveillance');
      expect(provider.popularBooks.length, 1);
      expect(provider.popularBooks.first.title, '1984');

      provider.dispose();
    });

    test('sorting: rating, pages, title without mutating source catalog',
        () async {
      final provider =
          CatalogProvider(manageCatalog: ManageCatalogUseCase(repo));
      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      // Sort by rating descending
      provider.setFilters(sortBy: 'rating');
      expect(provider.popularBooks.first.title, 'The Lord of the Rings'); // 4.9

      // Sort by pages ascending
      provider.setFilters(sortBy: 'pages');
      expect(provider.popularBooks.first.title, 'Unknown Pamphlet'); // 0 pages
      expect(provider.popularBooks.last.title,
          'The Lord of the Rings'); // 1178 pages

      // Sort by title ascending
      provider.setFilters(sortBy: 'title');
      expect(provider.popularBooks.first.title, '1984');

      // Verify source raw catalog data was not permanently mutated
      expect(provider.hasActiveFilters, isTrue);
      provider.clearFilters();
      expect(provider.hasActiveFilters, isFalse);
      expect(provider.popularBooks.length, 5);
      expect(provider.popularBooks.first.title,
          'Pride and Prejudice'); // original order restored

      provider.dispose();
    });

    test('clearFilters resets all filter state and restores catalog', () async {
      final provider =
          CatalogProvider(manageCatalog: ManageCatalogUseCase(repo));
      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      provider.setFilters(author: 'Nonexistent Author', pageRange: 3);
      expect(provider.popularBooks, isEmpty);
      expect(provider.hasActiveFilters, isTrue);

      provider.clearFilters();
      expect(provider.hasActiveFilters, isFalse);
      expect(provider.filterAuthor, '');
      expect(provider.filterPageRange, 0);
      expect(provider.popularBooks.length, 5);

      provider.dispose();
    });

    test('pagination: fetchMorePopular maintains active filters on new items',
        () async {
      final provider =
          CatalogProvider(manageCatalog: ManageCatalogUseCase(repo));
      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      provider.setFilters(author: 'Tolkien');
      expect(provider.popularBooks.length, 1);
      expect(provider.popularBooks.first.title, 'The Lord of the Rings');

      // Fetch more books containing another Tolkien book and an unrelated book
      repo.morePopularBooksResult = [
        const Book(
          isbn13: '9780261102217',
          title: 'The Hobbit',
          authors: 'J.R.R. Tolkien',
          categories: 'Fantasy',
          description: 'There and Back Again.',
          thumbnail: '',
          averageRating: 4.7,
          ratingsCount: 3000,
          publishedDate: '1937',
          pageCount: 310,
        ),
        const Book(
          isbn13: '9780140449136',
          title: 'Crime and Punishment',
          authors: 'Fyodor Dostoevsky',
          categories: 'Classic',
          description: 'A psychological novel.',
          thumbnail: '',
          averageRating: 4.3,
          ratingsCount: 1200,
          publishedDate: '1866',
          pageCount: 671,
        ),
      ];

      await provider.fetchMorePopular();
      // Should now contain both Tolkien books while excluding Dostoevsky
      expect(provider.popularBooks.length, 2);
      expect(provider.popularBooks.map((b) => b.title),
          containsAll(['The Lord of the Rings', 'The Hobbit']));

      provider.dispose();
    });
  });
}
