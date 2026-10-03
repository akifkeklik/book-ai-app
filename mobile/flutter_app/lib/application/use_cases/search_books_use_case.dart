import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';

class SearchBooksUseCase {
  final BookRepository _repository;

  SearchBooksUseCase(this._repository);

  Future<List<Book>> execute(String query) {
    return _repository.searchBooks(query);
  }
}
