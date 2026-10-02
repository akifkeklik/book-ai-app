
import 'package:flutter_test/flutter_test.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/providers/book_provider.dart';

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
  group('BookProvider.fetchPopular', () {
    test('success: loading -> loaded, books populated', () async {
      final repo = FakeBookRepository();
      repo.popularBooksResult = [
        FakeBookRepository.book('111', 'Book A'),
        FakeBookRepository.book('222', 'Book B'),
      ];
      // Disable cache so we start fresh
      final provider = BookProvider(repo);

      // Wait for constructor async calls to settle
      await Future.delayed(Duration.zero);

      await provider.fetchPopular(force: true);

      expect(provider.popularStatus, BookStatus.loaded);
      expect(provider.popularBooks.length, 2);
      expect(provider.popularBooks.first.title, 'Book A');
      expect(provider.popularError, isNull);
      provider.dispose();
    });

    test('failure: loading -> error, error message set', () async {
      final repo = FakeBookRepository();
      repo.popularBooksError = Exception('network timeout');
      final provider = BookProvider(repo);

      await Future.delayed(Duration.zero);

      await provider.fetchPopular(force: true);

      expect(provider.popularStatus, BookStatus.error);
      expect(provider.popularError, isNotNull);
      expect(provider.popularError, contains('network timeout'));
      provider.dispose();
    });

    test('duplicate request prevention: second call while loading is ignored', () async {

      final repo = FakeBookRepository();
      // Override via a subclass trick: count calls via the completer
      // Simpler: just track getPopularCallCount with a delayed result
      repo.popularBooksResult = [];

      final provider = BookProvider(repo);
      await Future.delayed(Duration.zero);

      // Force status to loading manually to test the guard
      // (without a real in-flight future we rely on the status guard)
      // We verify that calling fetchPopular twice rapidly does not double the network call

      // Reset count
      repo.getPopularCallCount = 0;
      // Start first call — it resolves synchronously in fake
      final f1 = provider.fetchPopular(force: true);
      // Start second call immediately — status is already 'loading' during f1
      final f2 = provider.fetchPopular(force: true);
      await Future.wait([f1, f2]);

      // Only 1 network call should have been made
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
      final provider = BookProvider(repo);

      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);

      expect(provider.popularStatus, BookStatus.loaded);
      expect(provider.popularBooks.map((b) => b.isbn13).toList(),
          containsAll(['A1', 'B2', 'C3']));
      provider.dispose();
    });

    test('retry after error: second fetchPopular succeeds', () async {
      final repo = FakeBookRepository();
      repo.popularBooksError = Exception('server error');
      final provider = BookProvider(repo);

      await Future.delayed(Duration.zero);
      await provider.fetchPopular(force: true);
      expect(provider.popularStatus, BookStatus.error);

      // Fix the repo and retry
      repo.popularBooksError = null;
      repo.popularBooksResult = [FakeBookRepository.book('X1', 'Recovered')];
      await provider.fetchPopular(force: true);

      expect(provider.popularStatus, BookStatus.loaded);
      expect(provider.popularBooks.first.title, 'Recovered');
      provider.dispose();
    });
  });

  group('BookProvider.fetchPersonalizedRecs - stale response protection', () {
    test('stale userId response does not overwrite newer userId state', () async {
      // Two sequential calls for different users.
      // Both resolve immediately in fake (no real async gap to exploit),
      // but the guard is: result is written only if _lastPersonalizedUserId matches.

      final repo = FakeBookRepository();
      repo.personalizedResult = [FakeBookRepository.book('P1', 'PersonalBook')];
      final provider = BookProvider(repo);

      await Future.delayed(Duration.zero);

      // Call for user-A
      await provider.fetchPersonalizedRecs('user-A');
      expect(provider.personalizedStatus, BookStatus.loaded);
      expect(provider.personalizedRecs.first.isbn13, 'P1');

      // Immediately switch to user-B (simulates user logout/login)
      repo.personalizedResult = [];
      await provider.fetchPersonalizedRecs('user-B');

      // Final state must belong to user-B request, not user-A
      expect(provider.personalizedStatus, BookStatus.loaded);
      expect(provider.personalizedRecs, isEmpty);
      provider.dispose();
    });

    test('personalized failure + fallback failure: status becomes error', () async {
      final repo = FakeBookRepository();
      repo.personalizedError = Exception('AI service down');
      repo.fallbackError = Exception('Fallback down');
      final provider = BookProvider(repo);

      await Future.delayed(Duration.zero);
      await provider.fetchPersonalizedRecs('user-1');

      expect(provider.personalizedStatus, BookStatus.error);
      provider.dispose();
    });
    test('clearUserData: clears personalized recs and status', () async {
      final repo = FakeBookRepository();
      repo.personalizedResult = [
        const Book(isbn13: '1', title: 'Personalized 1', authors: 'Author', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0)
      ];

      final provider = BookProvider(repo);

      // Load user A
      await provider.fetchPersonalizedRecs('userA');
      expect(provider.personalizedStatus, BookStatus.loaded);
      expect(provider.personalizedRecs, isNotEmpty);

      // Logout / Clear
      provider.clearUserData();
      expect(provider.personalizedStatus, BookStatus.initial);
      expect(provider.personalizedRecs, isEmpty);
    });

  });
}
