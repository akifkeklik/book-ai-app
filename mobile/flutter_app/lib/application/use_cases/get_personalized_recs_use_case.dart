import 'package:flutter/foundation.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';

class GetPersonalizedRecsUseCase {
  final BookRepository _repository;

  GetPersonalizedRecsUseCase(this._repository);

  Future<List<Book>> execute(String userId, List<Book> currentPopularBooks) async {
    try {
      final recs = await _repository.getPersonalizedRecommendations(userId);
      
      if (recs.isEmpty || _isTooSimilarToPopular(recs, currentPopularBooks)) {
        debugPrint('Personalized recs empty/similar to popular, trying fallback...');
        return await _getFallbackRecs(userId, currentPopularBooks);
      }
      
      return recs;
    } catch (e) {
      debugPrint('Personalized Recs error: $e. Using fallback...');
      return await _getFallbackRecs(userId, currentPopularBooks);
    }
  }

  Future<List<Book>> _getFallbackRecs(String userId, List<Book> currentPopularBooks) async {
    try {
      final recs = await _repository.getFallbackRecommendations(userId);
      return _dropTopPopularDuplicates(recs, currentPopularBooks);
    } catch (e) {
      debugPrint('Fallback Recs error: $e');
      throw Exception('Failed to get fallback recommendations');
    }
  }

  bool _isTooSimilarToPopular(List<Book> recs, List<Book> popularBooks) {
    if (recs.isEmpty || popularBooks.isEmpty) return false;

    final recTop = recs.take(6).map((b) => b.isbn13).toList();
    final popTop = popularBooks.take(6).map((b) => b.isbn13).toList();
    if (recTop.length == popTop.length &&
        recTop.isNotEmpty &&
        List.generate(recTop.length, (i) => recTop[i] == popTop[i])
            .every((v) => v)) {
      return true;
    }

    final popSet = popularBooks.take(12).map((b) => b.isbn13).toSet();
    final overlap =
        recs.take(12).where((b) => popSet.contains(b.isbn13)).length;
    return overlap >= 10;
  }

  List<Book> _dropTopPopularDuplicates(List<Book> source, List<Book> popularBooks) {
    if (popularBooks.isEmpty) return source;
    final popTopIds = popularBooks.take(8).map((b) => b.isbn13).toSet();
    final filtered =
        source.where((b) => !popTopIds.contains(b.isbn13)).toList();
    return filtered.isNotEmpty ? filtered : source;
  }
}
