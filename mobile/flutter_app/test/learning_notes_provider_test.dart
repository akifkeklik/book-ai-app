import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/domain/entities/learning_note.dart';
import 'package:book_ai_app/providers/notes_provider.dart';
import 'package:book_ai_app/services/api_service.dart';

class FakeTestApiService implements ApiService {
  final List<LearningNote> db = [];
  bool shouldFailAdd = false;
  bool shouldFailUpdate = false;
  bool shouldFailDelete = false;
  bool shouldFailFetch = false;

  @override
  Future<List<LearningNote>> getNotes({
    String? bookId,
    String? noteType,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    if (shouldFailFetch) throw Exception('Fetch failed');
    var list = List<LearningNote>.from(db);
    if (bookId != null && bookId.isNotEmpty) {
      list = list.where((n) => n.bookId == bookId).toList();
    }
    if (noteType != null && noteType.isNotEmpty) {
      list = list.where((n) => n.noteType == noteType).toList();
    }
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((n) => n.content.toLowerCase().contains(q) || n.bookId.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Future<LearningNote?> createNote({
    required String bookId,
    required String noteType,
    required String content,
    String? clientId,
  }) async {
    if (shouldFailAdd) return null;
    final note = LearningNote(
      id: 'server-note-${db.length + 1}',
      userId: 'test_user_1',
      bookId: bookId,
      noteType: noteType,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      clientId: clientId,
    );
    db.insert(0, note);
    return note;
  }

  @override
  Future<LearningNote?> updateNote({
    required String noteId,
    required String content,
    String? noteType,
  }) async {
    if (shouldFailUpdate) return null;
    final index = db.indexWhere((n) => n.id == noteId);
    if (index == -1) return null;
    final existing = db[index];
    final updated = existing.copyWith(
      content: content,
      noteType: noteType ?? existing.noteType,
      updatedAt: DateTime.now(),
    );
    db[index] = updated;
    return updated;
  }

  @override
  Future<bool> deleteNote({required String noteId}) async {
    if (shouldFailDelete) return false;
    final index = db.indexWhere((n) => n.id == noteId);
    if (index == -1) return false;
    db.removeAt(index);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('NotesProvider Unit & Isolation Tests', () {
    late FakeTestApiService fakeApi;
    late NotesProvider provider;

    setUp(() {
      fakeApi = FakeTestApiService();
      provider = NotesProvider(apiService: fakeApi);
    });

    test('Initial state is clean', () {
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.allNotes, isEmpty);
      expect(provider.getBookNotes('978-0141036144'), isEmpty);
      expect(provider.activeUserId, isNull);
    });

    test('loadBookNotes fetches and caches notes for a book', () async {
      fakeApi.db.add(LearningNote(
        id: 'note-1',
        userId: 'u1',
        bookId: '978-0141036144',
        noteType: 'personal_note',
        content: 'Fascinating world building',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await provider.loadBookNotes('978-0141036144', userId: 'u1');

      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
      final notes = provider.getBookNotes('978-0141036144');
      expect(notes.length, 1);
      expect(notes.first.content, 'Fascinating world building');
    });

    test('addNote optimistically adds note and replaces with server note on success', () async {
      final success = await provider.addNote(
        bookId: '978-0141036144',
        noteType: 'key_takeaway',
        content: 'Big brother is watching you is a cautionary metaphor',
        userId: 'u1',
      );

      expect(success, isTrue);
      final bookNotes = provider.getBookNotes('978-0141036144');
      expect(bookNotes.length, 1);
      expect(bookNotes.first.id, startsWith('server-note-'));
      expect(bookNotes.first.noteType, 'key_takeaway');
      expect(provider.allNotes.length, 1);
    });

    test('addNote rolls back optimistic update when server fails', () async {
      fakeApi.shouldFailAdd = true;

      final success = await provider.addNote(
        bookId: '978-0141036144',
        noteType: 'question',
        content: 'What happens next?',
        userId: 'u1',
      );

      expect(success, isFalse);
      expect(provider.getBookNotes('978-0141036144'), isEmpty);
      expect(provider.allNotes, isEmpty);
      expect(provider.errorMessage, isNotNull);
    });

    test('editNote optimistically updates and persists server change', () async {
      await provider.addNote(
        bookId: '978-0141036144',
        noteType: 'personal_note',
        content: 'Initial text',
        userId: 'u1',
      );

      final noteId = provider.getBookNotes('978-0141036144').first.id;

      final updated = await provider.editNote(
        noteId: noteId,
        bookId: '978-0141036144',
        content: 'Updated deep insight',
        noteType: 'key_takeaway',
      );

      expect(updated, isTrue);
      final note = provider.getBookNotes('978-0141036144').first;
      expect(note.content, 'Updated deep insight');
      expect(note.noteType, 'key_takeaway');
    });

    test('editNote rolls back when update fails', () async {
      await provider.addNote(
        bookId: '978-0141036144',
        noteType: 'personal_note',
        content: 'Original content',
        userId: 'u1',
      );

      final noteId = provider.getBookNotes('978-0141036144').first.id;
      fakeApi.shouldFailUpdate = true;

      final updated = await provider.editNote(
        noteId: noteId,
        bookId: '978-0141036144',
        content: 'This will fail',
      );

      expect(updated, isFalse);
      final note = provider.getBookNotes('978-0141036144').first;
      expect(note.content, 'Original content');
    });

    test('removeNote optimistically removes and confirms with server', () async {
      await provider.addNote(
        bookId: '978-0141036144',
        noteType: 'personal_note',
        content: 'Note to be deleted',
        userId: 'u1',
      );

      final noteId = provider.getBookNotes('978-0141036144').first.id;

      final removed = await provider.removeNote(
        noteId: noteId,
        bookId: '978-0141036144',
      );

      expect(removed, isTrue);
      expect(provider.getBookNotes('978-0141036144'), isEmpty);
      expect(provider.allNotes, isEmpty);
    });

    test('removeNote rolls back when deletion fails', () async {
      await provider.addNote(
        bookId: '978-0141036144',
        noteType: 'personal_note',
        content: 'Cannot delete me',
        userId: 'u1',
      );

      final noteId = provider.getBookNotes('978-0141036144').first.id;
      fakeApi.shouldFailDelete = true;

      final removed = await provider.removeNote(
        noteId: noteId,
        bookId: '978-0141036144',
      );

      expect(removed, isFalse);
      expect(provider.getBookNotes('978-0141036144').length, 1);
      expect(provider.allNotes.length, 1);
    });

    test('Account isolation: switching user clears cached notes immediately', () async {
      await provider.addNote(
        bookId: '978-0141036144',
        noteType: 'personal_note',
        content: 'User 1 private note',
        userId: 'user_1',
      );

      expect(provider.allNotes.length, 1);

      // Switching user clears state
      provider.setActiveUser('user_2');
      expect(provider.allNotes, isEmpty);
      expect(provider.getBookNotes('978-0141036144'), isEmpty);
      expect(provider.activeUserId, 'user_2');

      // Logout clears state completely
      provider.clear();
      expect(provider.activeUserId, isNull);
      expect(provider.allNotes, isEmpty);
      expect(provider.isLoading, isFalse);
    });
  });
}

