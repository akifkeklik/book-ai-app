import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../domain/entities/book.dart';
import '../application/use_cases/manage_recommendations_use_case.dart';

import '../data/repositories/favorites_outbox_repository.dart' show SyncResult;
import '../data/repositories/interactions_outbox_repository.dart';
import '../domain/entities/interaction_outbox_item.dart';
import '../services/api_service.dart';

enum RecommendationStatus { initial, loading, loaded, error }

class RecommendationProvider extends ChangeNotifier {
  final ManageRecommendationsUseCase _manageRecommendations;
  final InteractionsOutboxRepository _outboxRepo;

  RecommendationProvider({
    required ManageRecommendationsUseCase manageRecommendations,
    InteractionsOutboxRepository? outboxRepo,
  })  : _manageRecommendations = manageRecommendations,
        _outboxRepo = outboxRepo ?? InteractionsOutboxRepository();

  List<Book> _personalizedRecs = [];
  RecommendationStatus _status = RecommendationStatus.initial;
  String? _lastPersonalizedUserId;
  bool _excludeCompleted = false;
  bool _isColdStart = false;
  
  // We keep a reference to the latest popular books passed in
  // so that feedback/onboarding can refresh recommendations using them.
  List<Book> _lastPopularBooks = [];

  List<Book> get personalizedRecs => _personalizedRecs;
  RecommendationStatus get status => _status;
  bool get excludeCompleted => _excludeCompleted;
  bool get isColdStart => _isColdStart;

  Future<void> fetchPersonalizedRecs(String userId, List<Book> popularBooks, {bool force = false}) async {
    if (_status == RecommendationStatus.loading && _lastPersonalizedUserId == userId && !force) return;
    
    _lastPersonalizedUserId = userId;
    _lastPopularBooks = popularBooks;
    _status = RecommendationStatus.loading;
    _outboxRepo.resetAuthFailures(userId);
    notifyListeners();
    
    try {
      final recs = await _manageRecommendations.getPersonalizedRecs(
        userId,
        popularBooks,
        excludeCompleted: _excludeCompleted,
      );
      if (_lastPersonalizedUserId == userId) {
        _personalizedRecs = recs;
        _isColdStart = recs.isNotEmpty && (recs.first.isColdStart == true);
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
    _excludeCompleted = false;
    _isColdStart = false;
    notifyListeners();
  }

  void toggleExcludeCompleted(String userId) {
    _excludeCompleted = !_excludeCompleted;
    fetchPersonalizedRecs(userId, _lastPopularBooks, force: true);
  }

  Future<bool> resetPersonalization(String userId, [ApiService? apiService]) async {
    final api = apiService ?? ApiService.instance;
    final ok = await api.resetPersonalization(userId: userId);
    if (ok) {
      await fetchPersonalizedRecs(userId, _lastPopularBooks, force: true);
    }
    return ok;
  }

  Future<bool> submitFeedback({
    required String userId,
    required String bookId,
    required String interaction,
  }) async {
    // Optimistic UI
    final previousRecs = List<Book>.from(_personalizedRecs);
    if (interaction == 'dislike') {
      _personalizedRecs.removeWhere((b) => b.isbn13 == bookId);
      notifyListeners();
    }

    try {
      final success = await _manageRecommendations.submitFeedback(
        userId: userId,
        bookId: bookId,
        interaction: interaction,
      );

      if (success) {
        await fetchPersonalizedRecs(userId, _lastPopularBooks, force: true);
        return true;
      } else {
        // Enqueue offline mutation so user interaction is preserved
        await _outboxRepo.enqueue(
          userId: userId,
          isbn13: bookId,
          interaction: interaction,
        );
        return true; // Preserved in durable outbox
      }
    } catch (e) {
      final statusCode = e is DioException ? e.response?.statusCode : null;
      final errStr = e.toString().toLowerCase();
      final is4xx = statusCode == 400 ||
          statusCode == 422 ||
          errStr.contains('400') ||
          errStr.contains('422') ||
          errStr.contains('bad request') ||
          errStr.contains('invalid interaction');
      if (is4xx) {
        if (interaction == 'dislike') {
          _personalizedRecs = previousRecs;
          notifyListeners();
        }
        return false;
      }
      debugPrint('Feedback submission error: $e, queueing offline');
      try {
        await _outboxRepo.enqueue(
          userId: userId,
          isbn13: bookId,
          interaction: interaction,
        );
        return true; // Preserved in durable outbox
      } catch (queueErr) {
        if (interaction == 'dislike') {
          _personalizedRecs = previousRecs;
          notifyListeners();
        }
        return false;
      }
    }
  }

  bool hasPendingInteraction(String userId, String isbn13) =>
      _outboxRepo.hasPendingItem(userId, isbn13);

  List<InteractionOutboxItem> getPendingInteractions(String userId) =>
      _outboxRepo.getPendingItems(userId);

  Future<SyncResult> syncOfflineInteractions({
    required String userId,
    required ApiService apiService,
  }) async {
    _outboxRepo.resetAuthFailures(userId);
    final result = await _outboxRepo.syncUserOutbox(
      userId: userId,
      apiService: apiService,
    );
    if (result.synced > 0) {
      await fetchPersonalizedRecs(userId, _lastPopularBooks, force: true);
    }
    notifyListeners();
    return result;
  }

  Future<bool> submitOnboarding({
    required String userId,
    required List<String> bookIds,
    required List<String> genres,
  }) async {
    try {
      final success = await _manageRecommendations.submitOnboarding(
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
