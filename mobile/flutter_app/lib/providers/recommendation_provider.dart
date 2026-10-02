import 'package:flutter/material.dart';

import '../domain/entities/book.dart';
import '../domain/repositories/book_repository.dart';
import '../application/use_cases/get_personalized_recs_use_case.dart';

enum RecommendationStatus { initial, loading, loaded, error }

class RecommendationProvider extends ChangeNotifier {
  final BookRepository _repository;
  final GetPersonalizedRecsUseCase _getPersonalizedRecs;

  RecommendationProvider({
    required BookRepository repository,
    required GetPersonalizedRecsUseCase getPersonalizedRecs,
  })  : _repository = repository,
        _getPersonalizedRecs = getPersonalizedRecs;

  List<Book> _personalizedRecs = [];
  RecommendationStatus _status = RecommendationStatus.initial;
  String? _lastPersonalizedUserId;
  
  // We keep a reference to the latest popular books passed in
  // so that feedback/onboarding can refresh recommendations using them.
  List<Book> _lastPopularBooks = [];

  List<Book> get personalizedRecs => _personalizedRecs;
  RecommendationStatus get status => _status;

  Future<void> fetchPersonalizedRecs(String userId, List<Book> popularBooks, {bool force = false}) async {
    if (_status == RecommendationStatus.loading && _lastPersonalizedUserId == userId && !force) return;
    
    _lastPersonalizedUserId = userId;
    _lastPopularBooks = popularBooks;
    _status = RecommendationStatus.loading;
    notifyListeners();
    
    try {
      final recs = await _getPersonalizedRecs.execute(userId, popularBooks);
      if (_lastPersonalizedUserId == userId) {
        _personalizedRecs = recs;
        _status = RecommendationStatus.loaded;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Personalized Recs error: $e.');
      if (_lastPersonalizedUserId == userId) {
        _status = RecommendationStatus.error;
        notifyListeners();
      }
    }
  }

  void clearUserData() {
    _personalizedRecs = [];
    _status = RecommendationStatus.initial;
    _lastPersonalizedUserId = null;
    notifyListeners();
  }

  Future<void> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    // Optimistic UI
    if (interaction == 'dislike') {
      _personalizedRecs.removeWhere((b) => b.isbn13 == bookId);
      notifyListeners();
    }

    try {
      final success = await _repository.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: interaction,
      );

      if (success) {
        fetchPersonalizedRecs(userId, _lastPopularBooks, force: true);
      }
    } catch (e) {
      debugPrint('Feedback submission error: $e');
    }
  }

  Future<bool> submitOnboarding({
    required String userId,
    required List<String> bookIds,
    required List<String> genres,
  }) async {
    try {
      final success = await _repository.submitOnboarding(
        userId: userId,
        bookIds: bookIds,
        genres: genres,
      );
      if (success) {
        await fetchPersonalizedRecs(userId, _lastPopularBooks, force: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Onboarding submission error: $e');
      return false;
    }
  }
}
