import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';

class ManageCatalogUseCase {
  final BookRepository _repository;

  ManageCatalogUseCase(this._repository);

  Future<List<Book>> getPopularBooks({bool forceRefresh = false, int limit = 20}) async {
    final books = await _repository.getPopularBooks(limit: limit);
    _repository.savePopularBooksToCache(books);
    return books;
  }

  Future<List<Book>> getMorePopularBooks({required int offset, int limit = 20}) {
    return _repository.getMorePopularBooks(offset: offset, limit: limit);
  }

  Future<List<Map<String, dynamic>>> getCategories() {
    return _repository.getCategories();
  }

  Future<int> getTotalBookCount() {
    return _repository.getTotalBookCount();
  }

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
  }) {
    return _repository.getBooksByCategory(
      category: category,
      page: page,
      perPage: perPage,
      sort: sort,
      author: author,
      publisher: publisher,
      minPages: minPages,
      maxPages: maxPages,
      minRating: minRating,
      publishedFrom: publishedFrom,
      publishedTo: publishedTo,
    );
  }

  List<Book> getCachedPopularBooks() {
    return _repository.getCachedPopularBooks();
  }

  List<Book> getCachedCategoryBooks(String category) {
    return _repository.getCachedCategoryBooks(category);
  }

  void saveCategoryBooksToCache(String category, List<Book> books, {int? total, int? totalPages}) {
    _repository.saveCategoryBooksToCache(category, books, total: total, totalPages: totalPages);
  }
}
