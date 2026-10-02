import 'package:flutter_test/flutter_test.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/providers/catalog_provider.dart';
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/application/use_cases/get_popular_books_use_case.dart';
import 'package:book_ai_app/application/use_cases/get_personalized_recs_use_case.dart';

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

  @override
  Future<List<Book>> getMorePopularBooks({required int offset, int limit = 20}) async => [];

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
  Future<List<String>> getCategories() async => categoriesResult;

  @override
  Future<bool> submitFeedback({required String userId, required String bookId, required String interaction}) async => true;

  @override
  Future<bool> submitOnboarding({required String userId, required List<String> bookIds, required List<String> genres}) async => true;

  @override
  Future<Map<String, dynamic>> getBooksByCategory({required String category, int page = 1, int perPage = 40}) async => {};

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
  Future<void> trackActivity({required String userId, required String activityType, required String bookId}) async {}

  @override
  Future<Book?> getBookByIsbn(String isbn) async => null;

  @override
  Future<void> upsertUserProfile({required String userId, required List<String> preferredGenres, required int readingFrequency, required List<String> preferredAuthors, required String preferredVibe}) async {}

  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async => null;

  @override
  List<Book> getCachedPopularBooks() => cachedBooks;

  @override
  void savePopularBooksToCache(List<Book> books) => savedToCache = books;

  @override
  Future<int> getTotalBookCount() async => totalCount;
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
        repository: repo,
        getPopularBooks: GetPopularBooksUseCase(repo),
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
        repository: repo,
        getPopularBooks: GetPopularBooksUseCase(repo),
      );

      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.error);
      expect(provider.error, isNotNull);
      expect(provider.error, contains('network timeout'));
      provider.dispose();
    });

    test('duplicate request prevention: second call while loading is ignored', () async {
      final repo = FakeBookRepository();
      repo.popularBooksResult = [];

      final provider = CatalogProvider(
        repository: repo,
        getPopularBooks: GetPopularBooksUseCase(repo),
      );
      await Future.delayed(Duration.zero);

      repo.getPopularCallCount = 0;
      final f1 = provider.fetchPopular(force: true);
      final f2 = provider.fetchPopular(force: true);
      await Future.wait([f1, f2]);

      expect(repo.getPopularCallCount, 1);
      provider.dispose();
    });

    test('state correctness: after success, status is loaded and books match', () async {
      final repo = FakeBookRepository();
      final expected = [
        FakeBookRepository.book('A1', 'Alpha'),
        FakeBookRepository.book('B2', 'Beta'),
        FakeBookRepository.book('C3', 'Gamma'),
      ];
      repo.popularBooksResult = expected;
      final provider = CatalogProvider(
        repository: repo,
        getPopularBooks: GetPopularBooksUseCase(repo),
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
        repository: repo,
        getPopularBooks: GetPopularBooksUseCase(repo),
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

  group('RecommendationProvider.fetchPersonalizedRecs - stale response protection', () {
    test('stale userId response does not overwrite newer userId state', () async {
      final repo = FakeBookRepository();
      repo.personalizedResult = [FakeBookRepository.book('P1', 'PersonalBook')];
      final provider = RecommendationProvider(
        repository: repo,
        getPersonalizedRecs: GetPersonalizedRecsUseCase(repo),
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

    test('personalized failure + fallback failure: status becomes error', () async {
      final repo = FakeBookRepository();
      repo.personalizedError = Exception('AI service down');
      repo.fallbackError = Exception('Fallback down');
      final provider = RecommendationProvider(
        repository: repo,
        getPersonalizedRecs: GetPersonalizedRecsUseCase(repo),
      );

      await Future.delayed(Duration.zero);
      await provider.fetchPersonalizedRecs('user-1', []);

      expect(provider.status, RecommendationStatus.error);
      provider.dispose();
    });
    
    test('clearUserData: clears personalized recs and status', () async {
      final repo = FakeBookRepository();
      repo.personalizedResult = [
        const Book(isbn13: '1', title: 'Personalized 1', authors: 'Author', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0)
      ];

      final provider = RecommendationProvider(
        repository: repo,
        getPersonalizedRecs: GetPersonalizedRecsUseCase(repo),
      );

      await provider.fetchPersonalizedRecs('userA', []);
      expect(provider.status, RecommendationStatus.loaded);
      expect(provider.personalizedRecs, isNotEmpty);

      provider.clearUserData();
      expect(provider.status, RecommendationStatus.initial);
      expect(provider.personalizedRecs, isEmpty);
    });
  });
}
