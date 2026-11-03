import 'package:flutter/foundation.dart';
import '../domain/entities/book.dart';
import '../domain/entities/learning_path.dart';
import '../services/api_service.dart';

class LearningPathProvider extends ChangeNotifier {
  LearningPathProvider({ApiService? apiService})
      : _api = apiService ?? ApiService.instance;

  final ApiService _api;

  List<LearningPath> _paths = [];
  LearningPath? _activePath;
  List<Book> _suggestions = [];
  bool _isLoading = false;
  bool _isLoadingDetail = false;
  bool _isLoadingSuggestions = false;
  String? _error;
  String? _currentUserId;

  // Getters
  List<LearningPath> get paths => List.unmodifiable(_paths);
  LearningPath? get activePath => _activePath;
  List<Book> get suggestions => List.unmodifiable(_suggestions);
  bool get isLoading => _isLoading;
  bool get isLoadingDetail => _isLoadingDetail;
  bool get isLoadingSuggestions => _isLoadingSuggestions;
  String? get error => _error;

  /// Account isolation guard: resets all cached in-memory paths upon logout or user change.
  void updateUser(String? newUserId) {
    if (_currentUserId != newUserId) {
      _currentUserId = newUserId;
      _paths = [];
      _activePath = null;
      _suggestions = [];
      _error = null;
      notifyListeners();

      if (newUserId != null && newUserId.isNotEmpty) {
        loadPaths();
      }
    }
  }

  Future<void> loadPaths({String? status}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _api.getLearningPaths(status: status);
      _paths = res;
      if (_paths.isNotEmpty && _activePath == null) {
        await selectPath(_paths.first.id);
      }
    } catch (e) {
      _error = 'Failed to load learning paths';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectPath(String pathId) async {
    _isLoadingDetail = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _api.getLearningPathDetail(pathId);
      if (res != null) {
        _activePath = res;
        // Also fetch suggestions for path's category
        if (res.category != null && res.category!.isNotEmpty) {
          loadSuggestions(res.category!);
        } else {
          _suggestions = [];
        }
      }
    } catch (e) {
      _error = 'Failed to load path detail';
    } finally {
      _isLoadingDetail = false;
      notifyListeners();
    }
  }

  Future<LearningPath?> createPath({
    required String title,
    String? description,
    String? category,
    List<String>? bookIds,
  }) async {
    _error = null;
    try {
      final created = await _api.createLearningPath(
        title: title,
        description: description,
        category: category,
        bookIds: bookIds,
      );
      if (created != null) {
        _paths.insert(0, created);
        _activePath = created;
        notifyListeners();
        return created;
      }
      _error = 'Failed to create learning path';
    } catch (e) {
      _error = 'Error creating learning path: $e';
    }
    notifyListeners();
    return null;
  }

  Future<bool> updatePath(
    String pathId, {
    String? title,
    String? description,
    String? category,
    String? status,
  }) async {
    _error = null;
    try {
      final updated = await _api.updateLearningPath(
        pathId,
        title: title,
        description: description,
        category: category,
        status: status,
      );
      if (updated != null) {
        final idx = _paths.indexWhere((p) => p.id == pathId);
        if (idx != -1) {
          _paths[idx] = updated;
        }
        if (_activePath?.id == pathId) {
          _activePath = updated;
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'Error updating path: $e';
    }
    notifyListeners();
    return false;
  }

  Future<bool> deletePath(String pathId) async {
    final prevPaths = List<LearningPath>.from(_paths);
    _paths.removeWhere((p) => p.id == pathId);
    if (_activePath?.id == pathId) {
      _activePath = _paths.isNotEmpty ? _paths.first : null;
    }
    notifyListeners();

    try {
      final ok = await _api.deleteLearningPath(pathId);
      if (!ok) {
        // Rollback
        _paths = prevPaths;
        _error = 'Failed to delete learning path';
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _paths = prevPaths;
      _error = 'Error deleting learning path: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addBook(String pathId, String bookId) async {
    try {
      final updated = await _api.addBookToLearningPath(pathId, bookId);
      if (updated != null) {
        if (_activePath?.id == pathId) {
          _activePath = updated;
        }
        final idx = _paths.indexWhere((p) => p.id == pathId);
        if (idx != -1) {
          _paths[idx] = _paths[idx].copyWith(totalBooks: _paths[idx].totalBooks + 1);
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'Failed to add book';
    }
    notifyListeners();
    return false;
  }

  Future<bool> removeBook(String pathId, String bookId) async {
    try {
      final updated = await _api.removeBookFromLearningPath(pathId, bookId);
      if (updated != null) {
        if (_activePath?.id == pathId) {
          _activePath = updated;
        }
        final idx = _paths.indexWhere((p) => p.id == pathId);
        if (idx != -1) {
          _paths[idx] = _paths[idx].copyWith(
            totalBooks: (_paths[idx].totalBooks - 1).clamp(0, 9999),
          );
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'Failed to remove book';
    }
    notifyListeners();
    return false;
  }

  Future<bool> reorderBooks(String pathId, List<String> bookIds) async {
    if (_activePath == null) return false;

    // Optimistic reorder
    final currentBooks = List<LearningPathItem>.from(_activePath!.books);
    final map = {for (final b in currentBooks) b.bookId: b};
    final reordered = <LearningPathItem>[];
    for (int i = 0; i < bookIds.length; i++) {
      final item = map[bookIds[i]];
      if (item != null) {
        reordered.add(item.copyWith(orderIndex: i));
      }
    }
    _activePath = _activePath!.copyWith(books: reordered);
    notifyListeners();

    try {
      final updated = await _api.reorderLearningPathBooks(pathId, bookIds);
      if (updated != null) {
        _activePath = updated;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _activePath = _activePath!.copyWith(books: currentBooks);
      _error = 'Failed to reorder books';
      notifyListeners();
    }
    return false;
  }

  Future<void> loadSuggestions(String category) async {
    _isLoadingSuggestions = true;
    notifyListeners();
    try {
      final res = await _api.getLearningPathSuggestions(category: category, limit: 8);
      _suggestions = res;
    } catch (_) {
      _suggestions = [];
    } finally {
      _isLoadingSuggestions = false;
      notifyListeners();
    }
  }
}

