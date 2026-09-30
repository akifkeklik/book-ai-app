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
  
  // Cache methods
  List<Book> getCachedPopularBooks();
  void savePopularBooksToCache(List<Book> books);
  
  // Total count
  Future<int> getTotalBookCount();
}
