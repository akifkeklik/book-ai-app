import 'package:flutter/foundation.dart';
import '../data/repositories/notes_outbox_repository.dart';
import '../domain/entities/learning_note.dart';
import '../domain/entities/note_outbox_item.dart';
import '../services/api_service.dart';

class NotesProvider with ChangeNotifier {
  NotesProvider({
    required ApiService apiService,
    NotesOutboxRepository? outboxRepository,
  })  : _apiService = apiService,
        _outboxRepo = outboxRepository;

  final ApiService _apiService;
  final NotesOutboxRepository? _outboxRepo;

  final Map<String, List<LearningNote>> _bookNotes = {};
  List<LearningNote> _allNotes = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _activeUserId;

  // Smart review state
  List<Map<String, dynamic>> _dueReviews = [];
  Map<String, dynamic>? _reviewStats;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get activeUserId => _activeUserId;
  List<LearningNote> get allNotes => List.unmodifiable(_allNotes);
  List<Map<String, dynamic>> get dueReviews => List.unmodifiable(_dueReviews);
  Map<String, dynamic>? get reviewStats => _reviewStats;
  int get dueReviewCount => _dueReviews.length;

  List<LearningNote> getBookNotes(String bookId) {
    return List.unmodifiable(_bookNotes[bookId] ?? const []);
  }

  void setActiveUser(String? userId) {
    if (_activeUserId != userId) {
      _activeUserId = userId;
      _bookNotes.clear();
      _allNotes.clear();
      _dueReviews.clear();
      _reviewStats = null;
      _errorMessage = null;

      // Load cached notes for new active user immediately
      if (_outboxRepo != null && userId != null && userId.isNotEmpty) {
        final cached = _outboxRepo.getCachedNotes(userId);
        _allNotes = cached;
        for (final note in cached) {
          final list = _bookNotes[note.bookId] ?? [];
          _bookNotes[note.bookId] = [...list, note];
        }
      }
      notifyListeners();
    }
  }

  void clear() {
    _activeUserId = null;
    _bookNotes.clear();
    _allNotes.clear();
    _dueReviews.clear();
    _reviewStats = null;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> loadBookNotes(String bookId, {String? userId}) async {
    if (userId != null && _activeUserId != userId) {
      setActiveUser(userId);
    }

    final currentUid = _activeUserId ?? userId ?? '';

    // Step 1: Instant load from local persistent cache if available
    if (_outboxRepo != null && currentUid.isNotEmpty) {
      final cached = _outboxRepo.getCachedNotes(currentUid, bookId: bookId);
      if (cached.isNotEmpty) {
        _bookNotes[bookId] = cached;
        notifyListeners();
      }
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final notes = await _apiService.getNotes(bookId: bookId);
      
      if (_outboxRepo != null && currentUid.isNotEmpty) {
        // Persist fresh server notes in cache
        await _outboxRepo.saveCachedNotes(currentUid, notes);

        // Keep any pending local outbox creations that are not yet on the server
        final pendingCreates = _outboxRepo
            .getPendingItems(currentUid)
            .where((item) => item.bookId == bookId && item.action == NoteOutboxAction.create)
            .map((item) => LearningNote(
                  id: item.clientNoteId,
                  userId: currentUid,
                  bookId: item.bookId,
                  noteType: item.noteType,
                  content: item.content,
                  createdAt: item.createdAt,
                  updatedAt: item.createdAt,
                  isPendingSync: true,
                  clientId: item.clientNoteId,
                  bookTitle: item.bookTitle,
                  bookAuthor: item.bookAuthor,
                  bookThumbnail: item.bookThumbnail,
                ))
            .toList();

        final combined = [...pendingCreates, ...notes];
        _bookNotes[bookId] = combined;
      } else {
        _bookNotes[bookId] = notes;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      // If we have cached notes, retain them gracefully without showing a blank screen
      if ((_bookNotes[bookId] ?? []).isEmpty) {
        _errorMessage = 'Failed to load notes for book';
      }
      notifyListeners();
    }
  }

  Future<void> loadAllNotes({
    String? userId,
    String? noteType,
    String? query,
  }) async {
    if (userId != null && _activeUserId != userId) {
      setActiveUser(userId);
    }

    final currentUid = _activeUserId ?? userId ?? '';

    if (_outboxRepo != null && currentUid.isNotEmpty) {
      final cached = _outboxRepo.getCachedNotes(
        currentUid,
        noteType: noteType,
        query: query,
      );
      if (cached.isNotEmpty) {
        _allNotes = cached;
        notifyListeners();
      }
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final notes = await _apiService.getNotes(
        noteType: noteType,
        query: query,
        limit: 100,
      );

      if (_outboxRepo != null && currentUid.isNotEmpty) {
        await _outboxRepo.saveCachedNotes(currentUid, notes);
        final pendingCreates = _outboxRepo
            .getPendingItems(currentUid)
            .where((item) => item.action == NoteOutboxAction.create)
            .map((item) => LearningNote(
                  id: item.clientNoteId,
                  userId: currentUid,
                  bookId: item.bookId,
                  noteType: item.noteType,
                  content: item.content,
                  createdAt: item.createdAt,
                  updatedAt: item.createdAt,
                  isPendingSync: true,
                  clientId: item.clientNoteId,
                  bookTitle: item.bookTitle,
                  bookAuthor: item.bookAuthor,
                  bookThumbnail: item.bookThumbnail,
                ))
            .toList();

        _allNotes = [...pendingCreates, ...notes];
      } else {
        _allNotes = notes;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      if (_allNotes.isEmpty) {
        _errorMessage = 'Failed to load all notes';
      }
      notifyListeners();
    }
  }

  Future<bool> addNote({
    required String bookId,
    required String noteType,
    required String content,
    required String userId,
    String? bookTitle,
    String? bookAuthor,
    String? bookThumbnail,
  }) async {
    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final optimisticNote = LearningNote(
      id: tempId,
      userId: userId,
      bookId: bookId,
      noteType: noteType,
      content: content.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookThumbnail: bookThumbnail,
      isPendingSync: _outboxRepo != null,
      clientId: tempId,
    );

    // Optimistic insert into in-memory lists
    final prevList = _bookNotes[bookId] ?? [];
    _bookNotes[bookId] = [optimisticNote, ...prevList];
    _allNotes = [optimisticNote, ..._allNotes];
    notifyListeners();

    if (_outboxRepo != null) {
      // ── OFFLINE-FIRST OUTBOX FLOW ──────────────────────────────────────────
      await _outboxRepo.saveCachedNote(userId, optimisticNote);
      await _outboxRepo.enqueueCreate(
        userId: userId,
        clientNoteId: tempId,
        bookId: bookId,
        noteType: noteType,
        content: content.trim(),
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        bookThumbnail: bookThumbnail,
      );

      // Attempt immediate background sync
      try {
        final created = await _apiService.createNote(
          bookId: bookId,
          noteType: noteType,
          content: content.trim(),
          clientId: tempId,
        );

        if (created != null) {
          await _outboxRepo.removeCachedNote(userId, tempId);
          await _outboxRepo.saveCachedNote(
            userId,
            created.copyWith(
              isPendingSync: false,
              isSyncFailed: false,
              clientId: tempId,
            ),
          );
          await _outboxRepo.removeItem(userId, tempId);

          _bookNotes[bookId] = (_bookNotes[bookId] ?? [])
              .map((n) => n.id == tempId ? created : n)
              .toList();
          _allNotes = _allNotes.map((n) => n.id == tempId ? created : n).toList();
          notifyListeners();
        }
      } catch (e) {
        debugPrint('[NotesProvider] Network deferred sync for note $tempId: $e');
        // Note safely remains in queue and cache
      }

      return true;
    }

    // ── LEGACY IN-MEMORY OPTIMISTIC ROLLBACK FLOW (when no outbox repo) ──────
    try {
      final created = await _apiService.createNote(
        bookId: bookId,
        noteType: noteType,
        content: content.trim(),
      );

      if (created != null) {
        _bookNotes[bookId] = (_bookNotes[bookId] ?? [])
            .map((n) => n.id == tempId ? created : n)
            .toList();
        _allNotes = _allNotes.map((n) => n.id == tempId ? created : n).toList();
        notifyListeners();
        return true;
      } else {
        _bookNotes[bookId] = prevList;
        _allNotes = _allNotes.where((n) => n.id != tempId).toList();
        _errorMessage = 'Failed to create note';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _bookNotes[bookId] = prevList;
      _allNotes = _allNotes.where((n) => n.id != tempId).toList();
      _errorMessage = 'Network error while creating note';
      notifyListeners();
      return false;
    }
  }

  Future<bool> editNote({
    required String noteId,
    required String bookId,
    required String content,
    String? noteType,
  }) async {
    final prevList = _bookNotes[bookId] ?? [];
    final prevNote = prevList.where((n) => n.id == noteId).firstOrNull;
    if (prevNote == null) return false;

    final updatedOptimistic = prevNote.copyWith(
      content: content.trim(),
      noteType: noteType ?? prevNote.noteType,
      updatedAt: DateTime.now(),
      isPendingSync: _outboxRepo != null,
    );

    _bookNotes[bookId] = prevList.map((n) => n.id == noteId ? updatedOptimistic : n).toList();
    _allNotes = _allNotes.map((n) => n.id == noteId ? updatedOptimistic : n).toList();
    notifyListeners();

    if (_outboxRepo != null && _activeUserId != null) {
      await _outboxRepo.saveCachedNote(_activeUserId!, updatedOptimistic);
      await _outboxRepo.enqueueUpdate(
        userId: _activeUserId!,
        clientNoteId: prevNote.clientId ?? noteId,
        serverId: prevNote.clientId != null ? (noteId.startsWith('temp-') ? null : noteId) : noteId,
        bookId: bookId,
        content: content.trim(),
        noteType: noteType,
      );

      try {
        final updated = await _apiService.updateNote(
          noteId: noteId,
          content: content.trim(),
          noteType: noteType,
        );

        if (updated != null) {
          await _outboxRepo.saveCachedNote(_activeUserId!, updated);
          await _outboxRepo.removeItem(_activeUserId!, prevNote.clientId ?? noteId);
          _bookNotes[bookId] = (_bookNotes[bookId] ?? [])
              .map((n) => n.id == noteId ? updated : n)
              .toList();
          _allNotes = _allNotes.map((n) => n.id == noteId ? updated : n).toList();
          notifyListeners();
        }
      } catch (e) {
        debugPrint('[NotesProvider] Deferring update note sync: $e');
      }

      return true;
    }

    try {
      final updated = await _apiService.updateNote(
        noteId: noteId,
        content: content.trim(),
        noteType: noteType,
      );

      if (updated != null) {
        _bookNotes[bookId] = (_bookNotes[bookId] ?? [])
            .map((n) => n.id == noteId ? updated : n)
            .toList();
        _allNotes = _allNotes.map((n) => n.id == noteId ? updated : n).toList();
        notifyListeners();
        return true;
      } else {
        _bookNotes[bookId] = prevList;
        _allNotes = _allNotes.map((n) => n.id == noteId ? prevNote : n).toList();
        _errorMessage = 'Failed to update note';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _bookNotes[bookId] = prevList;
      _allNotes = _allNotes.map((n) => n.id == noteId ? prevNote : n).toList();
      _errorMessage = 'Network error while updating note';
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeNote({
    required String noteId,
    required String bookId,
  }) async {
    final prevList = _bookNotes[bookId] ?? [];
    final prevNote = prevList.where((n) => n.id == noteId).firstOrNull;
    if (prevNote == null) return false;

    _bookNotes[bookId] = prevList.where((n) => n.id != noteId).toList();
    _allNotes = _allNotes.where((n) => n.id != noteId).toList();
    notifyListeners();

    if (_outboxRepo != null && _activeUserId != null) {
      await _outboxRepo.removeCachedNote(_activeUserId!, noteId);
      await _outboxRepo.enqueueDelete(
        userId: _activeUserId!,
        clientNoteId: prevNote.clientId ?? noteId,
        serverId: noteId.startsWith('temp-') ? null : noteId,
        bookId: bookId,
      );

      try {
        if (!noteId.startsWith('temp-')) {
          await _apiService.deleteNote(noteId: noteId);
        }
        await _outboxRepo.removeItem(_activeUserId!, prevNote.clientId ?? noteId);
      } catch (e) {
        debugPrint('[NotesProvider] Deferring delete note sync: $e');
      }

      return true;
    }

    try {
      final ok = await _apiService.deleteNote(noteId: noteId);
      if (ok) {
        return true;
      } else {
        _bookNotes[bookId] = prevList;
        _allNotes = [..._allNotes, prevNote];
        _errorMessage = 'Failed to delete note';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _bookNotes[bookId] = prevList;
      _allNotes = [..._allNotes, prevNote];
      _errorMessage = 'Network error while deleting note';
      notifyListeners();
      return false;
    }
  }

  // ── Smart Review & Recall Lifecycle ─────────────────────────────────────────

  Future<void> loadDueReviews({int limit = 50}) async {
    try {
      final reviews = await _apiService.getDueReviews(limit: limit);
      _dueReviews = reviews;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotesProvider] loadDueReviews error: $e');
    }
  }

  Future<void> loadReviewStats() async {
    try {
      final stats = await _apiService.getReviewStats();
      _reviewStats = stats;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotesProvider] loadReviewStats error: $e');
    }
  }

  Future<bool> submitReview({required String noteId, required String outcome}) async {
    // Optimistic removal from due reviews list
    final prevReviews = List<Map<String, dynamic>>.from(_dueReviews);
    _dueReviews = _dueReviews.where((r) => (r['note_id'] ?? r['note']?['id']) != noteId).toList();
    notifyListeners();

    try {
      final ok = await _apiService.submitReview(noteId: noteId, outcome: outcome);
      if (ok) {
        // Refresh review stats
        await loadReviewStats();
        return true;
      } else {
        _dueReviews = prevReviews;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _dueReviews = prevReviews;
      notifyListeners();
      return false;
    }
  }

  // ── Notes Export ────────────────────────────────────────────────────────────

  Future<String?> exportNotesMarkdown({String? bookId}) async {
    return _apiService.exportNotesMarkdown(bookId: bookId);
  }
}
