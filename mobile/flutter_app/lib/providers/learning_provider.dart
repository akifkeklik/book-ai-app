import 'package:flutter/foundation.dart';
import '../domain/entities/learning_outcome.dart';
import '../services/api_service.dart';

class LearningProvider extends ChangeNotifier {
  LearningProvider({ApiService? apiService})
      : _api = apiService ?? ApiService.instance;

  final ApiService _api;

  LearningProgress? _progress;
  List<ReviewItem> _queue = const [];
  List<ReviewAttempt> _history = const [];
  List<DifficultConcept> _concepts = const [];
  ReviewItem? _activeItem;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;
  String? _currentUserId;
  String? _selectedConceptFilter;
  String? _selectedPathFilter;
  Map<String, dynamic>? _lastAttemptResult;

  // Getters
  LearningProgress? get progress => _progress;
  List<ReviewItem> get queue => _queue;
  List<ReviewAttempt> get history => _history;
  List<DifficultConcept> get concepts => _concepts;
  ReviewItem? get activeItem => _activeItem;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  String? get currentUserId => _currentUserId;
  String? get selectedConceptFilter => _selectedConceptFilter;
  String? get selectedPathFilter => _selectedPathFilter;
  Map<String, dynamic>? get lastAttemptResult => _lastAttemptResult;

  double get masteryScore => _progress?.masteryScore ?? 0.0;
  String get masteryLevel => _progress?.masteryLevel ?? 'insufficient_data';
  int get reviewsDue => _progress?.reviewsDue ?? 0;
  int get reviewsCompleted => _progress?.reviewsCompleted ?? 0;
  int get successfulRecalls => _progress?.successfulRecalls ?? 0;
  int get struggledRecalls => _progress?.struggledRecalls ?? 0;
  double get retentionRate => _progress?.retentionRate ?? 0.0;
  int get activeStreakDays => _progress?.activeStreakDays ?? 0;
  List<DifficultConcept> get difficultConcepts =>
      _progress?.difficultConcepts.isNotEmpty == true
          ? _progress!.difficultConcepts
          : _concepts;
  List<ReviewAttempt> get recentActivity =>
      _progress?.recentActivity.isNotEmpty == true
          ? _progress!.recentActivity
          : _history;

  /// Account isolation: clears memory state on logout or account switch.
  void updateUser(String? newUserId) {
    if (_currentUserId != newUserId) {
      _currentUserId = newUserId;
      _progress = null;
      _queue = const [];
      _history = const [];
      _concepts = const [];
      _activeItem = null;
      _error = null;
      _lastAttemptResult = null;
      _selectedConceptFilter = null;
      _selectedPathFilter = null;
      notifyListeners();

      if (newUserId != null && newUserId.isNotEmpty) {
        loadAll();
      }
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void setActiveItem(ReviewItem? item) {
    _activeItem = item;
    notifyListeners();
  }

  void filterByConcept(String? concept) {
    _selectedConceptFilter = concept;
    notifyListeners();
    loadQueue(concept: concept, pathId: _selectedPathFilter);
  }

  void filterByPath(String? pathId) {
    _selectedPathFilter = pathId;
    notifyListeners();
    loadQueue(concept: _selectedConceptFilter, pathId: pathId);
  }

  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.getLearningOverview(),
        _api.getLearningQueue(concept: _selectedConceptFilter, pathId: _selectedPathFilter),
        _api.getLearningHistory(limit: 20),
        _api.getLearningConcepts(),
      ]);

      _progress = results[0] as LearningProgress?;
      _queue = (results[1] as List<ReviewItem>?) ?? const [];
      _history = (results[2] as List<ReviewAttempt>?) ?? const [];
      _concepts = (results[3] as List<DifficultConcept>?) ?? const [];

      if (_queue.isNotEmpty) {
        if (_activeItem == null || !_queue.any((q) => q.id == _activeItem!.id)) {
          _activeItem = _queue.first;
        }
      } else {
        _activeItem = null;
      }
    } catch (e) {
      _error = 'Failed to load learning data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadOverview() async {
    try {
      final p = await _api.getLearningOverview();
      if (p != null) {
        _progress = p;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[LearningProvider] loadOverview error: $e');
    }
  }

  Future<void> loadQueue({String? concept, String? pathId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final items = await _api.getLearningQueue(
        concept: concept ?? _selectedConceptFilter,
        pathId: pathId ?? _selectedPathFilter,
      );
      _queue = items;
      if (_queue.isNotEmpty) {
        if (_activeItem == null || !_queue.any((q) => q.id == _activeItem!.id)) {
          _activeItem = _queue.first;
        }
      } else {
        _activeItem = null;
      }
    } catch (e) {
      _error = 'Failed to load review queue: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory() async {
    try {
      final h = await _api.getLearningHistory(limit: 30);
      _history = h;
      notifyListeners();
    } catch (e) {
      debugPrint('[LearningProvider] loadHistory error: $e');
    }
  }

  Future<void> loadConcepts() async {
    try {
      final c = await _api.getLearningConcepts();
      _concepts = c;
      notifyListeners();
    } catch (e) {
      debugPrint('[LearningProvider] loadConcepts error: $e');
    }
  }

  Future<Map<String, dynamic>?> submitAttempt({
    required String itemId,
    required String outcome,
    String responseText = '',
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _api.submitLearningAttempt(
        itemId: itemId,
        outcome: outcome,
        responseText: responseText,
      );

      if (res != null) {
        _lastAttemptResult = res;

        // Advance or update queue
        final currentIdx = _queue.indexWhere((it) => it.id == itemId);
        if (currentIdx != -1) {
          final updatedList = List<ReviewItem>.from(_queue);
          final updatedItem = res['item'] as ReviewItem?;
          if (updatedItem != null) {
            // Remove current item from due queue if next review is in future
            if (updatedItem.isDue) {
              // Move to end of session
              updatedList.removeAt(currentIdx);
              updatedList.add(updatedItem);
            } else {
              updatedList.removeAt(currentIdx);
            }
          } else {
            updatedList.removeAt(currentIdx);
          }
          _queue = updatedList;

          // Next active card
          if (_queue.isNotEmpty) {
            _activeItem = _queue.first;
          } else {
            _activeItem = null;
          }
        }

        // Refresh overview and history in background
        loadOverview();
        loadHistory();
        loadConcepts();

        return res;
      } else {
        _error = 'Failed to record review outcome';
        return null;
      }
    } catch (e) {
      _error = 'Error submitting review attempt: $e';
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<ReviewItem?> createQuestion({
    required String title,
    required String concept,
    required String question,
    required String answer,
    String? explanation,
    String? bookId,
    String? pathId,
    String sourceType = 'custom_question',
    String? sourceId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newItem = await _api.createLearningItem(
        title: title,
        concept: concept,
        question: question,
        answer: answer,
        explanation: explanation,
        bookId: bookId,
        pathId: pathId,
        sourceType: sourceType,
        sourceId: sourceId,
      );

      if (newItem != null) {
        _queue = [newItem, ..._queue];
        _activeItem ??= newItem;
        loadOverview();
        return newItem;
      } else {
        _error = 'Failed to create review item';
        return null;
      }
    } catch (e) {
      _error = 'Error creating review item: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteItem(String itemId) async {
    try {
      final ok = await _api.deleteLearningItem(itemId);
      if (ok) {
        _queue = _queue.where((it) => it.id != itemId).toList();
        if (_activeItem?.id == itemId) {
          _activeItem = _queue.isNotEmpty ? _queue.first : null;
        }
        loadOverview();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[LearningProvider] deleteItem error: $e');
      return false;
    }
  }

  void nextCard() {
    if (_queue.isEmpty) {
      _activeItem = null;
      notifyListeners();
      return;
    }

    final currentIdx = _queue.indexWhere((it) => it.id == _activeItem?.id);
    if (currentIdx != -1 && currentIdx + 1 < _queue.length) {
      _activeItem = _queue[currentIdx + 1];
    } else {
      _activeItem = _queue.first;
    }
    notifyListeners();
  }
}
