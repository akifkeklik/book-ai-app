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

  Future<List<String>> getCategories() {
    return _repository.getCategories();
  }

  Future<int> getTotalBookCount() {
    return _repository.getTotalBookCount();
  }

  Future<Map<String, dynamic>> getBooksByCategory({required String category, int page = 1, int perPage = 40}) {
    return _repository.getBooksByCategory(category: category, page: page, perPage: perPage);
  }

  List<Book> getCachedPopularBooks() {
    return _repository.getCachedPopularBooks();
  }
}
