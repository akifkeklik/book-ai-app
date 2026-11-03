import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';

class SearchBooksUseCase {
  final BookRepository _repository;

  SearchBooksUseCase(this._repository);

  Future<List<Book>> execute(String query) async {
    final results = await _repository.searchBooks(query);
    if (results.isNotEmpty) {
      _repository.saveSearchResultsToCache(query, results);
    }
    return results;
  }

  List<Book> getCached(String query) {
    return _repository.getCachedSearchResults(query);
  }
}
