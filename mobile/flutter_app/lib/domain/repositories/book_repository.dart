import '../entities/book.dart';

abstract class BookRepository {
  Future<List<Book>> getPopularBooks({int limit = 20});
  Future<List<Book>> getMorePopularBooks({required int offset, int limit = 20});
  Future<List<Book>> getPersonalizedRecommendations(String userId);
  Future<List<Book>> getFallbackRecommendations(String userId);
  Future<List<Book>> searchBooks(String query);
  Future<List<String>> getCategories();
  
  Future<bool> submitFeedback({required String userId, required String bookId, required String interaction});
  Future<bool> submitOnboarding({required String userId, required List<String> bookIds, required List<String> genres});
  
  // UI Specific Methods that were leaking Infrastructure
  Future<Map<String, dynamic>> getBooksByCategory({required String category, int page = 1, int perPage = 40});
  Future<Map<String, dynamic>> chatWithAI(String query);
  Future<List<Book>> getRecommendations(String title);
  Future<void> trackActivity({required String userId, required String activityType, required String bookId});
  Future<Book?> getBookByIsbn(String isbn);
  Future<void> upsertUserProfile({required String userId, required List<String> preferredGenres, required int readingFrequency, required List<String> preferredAuthors, required String preferredVibe});
  Future<Map<String, dynamic>?> getUserProfile(String userId);

  // Cache methods
  List<Book> getCachedPopularBooks();
  void savePopularBooksToCache(List<Book> books);
  
  // Total count
  Future<int> getTotalBookCount();
}
