import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';

class GetPopularBooksUseCase {
  final BookRepository _repository;

  GetPopularBooksUseCase(this._repository);

  Future<List<Book>> execute({bool forceRefresh = false}) async {
    // Note: Caching interval logic could be here, but we pass 'forceRefresh'
    final books = await _repository.getPopularBooks(limit: 20);
    _repository.savePopularBooksToCache(books);
    return books;
  }
}
