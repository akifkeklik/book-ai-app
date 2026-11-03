import '../entities/book.dart';

abstract class BookRepository {
  Future<List<Book>> getPopularBooks({int limit = 20});
  Future<List<Book>> getMorePopularBooks({required int offset, int limit = 20});
  Future<List<Book>> getPersonalizedRecommendations(String userId);
  Future<List<Book>> getFallbackRecommendations(String userId);
  Future<List<Book>> searchBooks(String query);
  Future<List<Map<String, dynamic>>> getCategories();
  
  Future<bool> submitFeedback({required String userId, required String bookId, required String interaction});
  Future<bool> submitOnboarding({required String userId, required List<String> bookIds, required List<String> genres});
  
  // UI Specific Methods that were leaking Infrastructure
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
  });
  Future<Map<String, dynamic>> chatWithAI(String query);
  Future<List<Book>> getRecommendations(String title);
  Future<void> trackActivity({required String userId, required String activityType, required String bookId});
  Future<Book?> getBookByIsbn(String isbn);
  Future<String?> getUserInteraction(String userId, String bookId);
  Future<void> upsertUserProfile({required String userId, required List<String> preferredGenres, required int readingFrequency, required List<String> preferredAuthors, required String preferredVibe});
  Future<Map<String, dynamic>?> getUserProfile(String userId);

  // Cache methods
  List<Book> getCachedPopularBooks();
  void savePopularBooksToCache(List<Book> books);
  List<Book> getCachedSearchResults(String query);
  void saveSearchResultsToCache(String query, List<Book> books);
  List<Book> getCachedCategoryBooks(String category);
  void saveCategoryBooksToCache(String category, List<Book> books, {int? total, int? totalPages});
  void clearUserCache(String userId);
  
  // Total count
  Future<int> getTotalBookCount();
}
