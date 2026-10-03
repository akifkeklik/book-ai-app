import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';

class ViewBookDetailsUseCase {
  final BookRepository _repository;

  ViewBookDetailsUseCase(this._repository);

  Future<Book?> getBookByIsbn(String isbn) {
    return _repository.getBookByIsbn(isbn);
  }

  Future<List<Book>> getSimilarBooks(String title) {
    return _repository.getRecommendations(title);
  }
}
