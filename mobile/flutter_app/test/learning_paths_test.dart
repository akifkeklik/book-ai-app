import 'package:flutter_test/flutter_test.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/entities/learning_path.dart';
import 'package:book_ai_app/providers/learning_path_provider.dart';
import 'package:book_ai_app/services/api_service.dart';

class FakeLearningPathsApiService implements ApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final List<LearningPath> paths = [];
  bool shouldFail = false;
  String currentUserId = 'user-a';
  int _idCounter = 0;

  @override
  Future<List<LearningPath>> getLearningPaths({String? status}) async {
    if (shouldFail) throw Exception('API Error');
    return paths.where((p) => p.userId == currentUserId).toList();
  }

  @override
  Future<LearningPath?> getLearningPathDetail(String pathId) async {
    if (shouldFail) throw Exception('API Error');
    final match = paths.where((p) => p.id == pathId).toList();
    return match.isNotEmpty ? match.first : null;
  }

  @override
  Future<LearningPath?> createLearningPath({
    required String title,
    String? description,
    String? category,
    List<String>? bookIds,
  }) async {
    if (shouldFail) throw Exception('API Error');
    final newPath = LearningPath(
      id: 'path-${DateTime.now().microsecondsSinceEpoch}-${++_idCounter}',
      userId: currentUserId,
      title: title,
      description: description,
      category: category,
      books: (bookIds ?? [])
          .asMap()
          .entries
          .map((e) => LearningPathItem(bookId: e.value, orderIndex: e.key))
          .toList(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      totalBooks: bookIds?.length ?? 0,
    );
    paths.insert(0, newPath);
    return newPath;
  }

  @override
  Future<LearningPath?> updateLearningPath(
    String pathId, {
    String? title,
    String? description,
    String? category,
    String? status,
  }) async {
    if (shouldFail) throw Exception('API Error');
    final idx = paths.indexWhere((p) => p.id == pathId);
    if (idx != -1) {
      final updated = paths[idx].copyWith(
        title: title,
        description: description,
        category: category,
        status: status,
      );
      paths[idx] = updated;
      return updated;
    }
    return null;
  }

  @override
  Future<bool> deleteLearningPath(String pathId) async {
    if (shouldFail) return false;
    final before = paths.length;
    paths.removeWhere((p) => p.id == pathId);
    return paths.length < before;
  }

  @override
  Future<LearningPath?> addBookToLearningPath(String pathId, String bookId, {int? orderIndex}) async {
    if (shouldFail) throw Exception('API Error');
    final idx = paths.indexWhere((p) => p.id == pathId);
    if (idx != -1) {
      final current = paths[idx];
      final newBooks = List<LearningPathItem>.from(current.books);
      newBooks.add(LearningPathItem(bookId: bookId, orderIndex: newBooks.length));
      final updated = current.copyWith(
        books: newBooks,
        totalBooks: newBooks.length,
      );
      paths[idx] = updated;
      return updated;
    }
    return null;
  }

  @override
  Future<LearningPath?> removeBookFromLearningPath(String pathId, String bookId) async {
    if (shouldFail) throw Exception('API Error');
    final idx = paths.indexWhere((p) => p.id == pathId);
    if (idx != -1) {
      final current = paths[idx];
      final newBooks = current.books.where((b) => b.bookId != bookId).toList();
      final updated = current.copyWith(
        books: newBooks,
        totalBooks: newBooks.length,
      );
      paths[idx] = updated;
      return updated;
    }
    return null;
  }

  @override
  Future<LearningPath?> reorderLearningPathBooks(String pathId, List<String> bookIds) async {
    if (shouldFail) throw Exception('API Error');
    final idx = paths.indexWhere((p) => p.id == pathId);
    if (idx != -1) {
      final current = paths[idx];
      final map = {for (final b in current.books) b.bookId: b};
      final reordered = <LearningPathItem>[];
      for (int i = 0; i < bookIds.length; i++) {
        final b = map[bookIds[i]];
        if (b != null) reordered.add(b.copyWith(orderIndex: i));
      }
      final updated = current.copyWith(books: reordered);
      paths[idx] = updated;
      return updated;
    }
    return null;
  }

  @override
  Future<List<Book>> getLearningPathSuggestions({
    String? category,
    String? query,
    int limit = 10,
  }) async {
    return [
      const Book(
        isbn13: '9780141439518',
        title: 'Pride and Prejudice',
        authors: 'Jane Austen',
        categories: 'Classics',
        thumbnail: '',
        averageRating: 4.5,
        ratingsCount: 100,
        publishedDate: '1813',
        pageCount: 300,
        description: 'A classic novel of manners',
      ),
    ];
  }
}

void main() {
  group('LearningPath & LearningPathItem Entity Tests', () {
    test('JSON serialization & deserialization with progress intelligence', () {
      final raw = {
        'id': 'path-001',
        'user_id': 'user-123',
        'title': 'Philosophy 101',
        'description': 'Introductory stoicism',
        'category': 'Philosophy',
        'status': 'active',
        'created_at': '2026-10-27T10:00:00Z',
        'updated_at': '2026-10-27T10:00:00Z',
        'books': [
          {
            'book_id': '9780141439518',
            'order_index': 0,
            'reading_status': 'finished',
            'notes_count': 2,
            'has_due_review': false,
            'book': {
              'isbn13': '9780141439518',
              'title': 'Pride and Prejudice',
              'authors': 'Jane Austen',
            },
          },
          {
            'book_id': '9780451524935',
            'order_index': 1,
            'reading_status': 'reading',
            'notes_count': 1,
            'has_due_review': true,
          },
        ],
        'total_books': 2,
        'completed_books': 1,
        'reading_books': 1,
        'not_started_books': 0,
        'progress_percent': 50,
        'total_notes_count': 3,
        'total_reviews_due': 1,
        'next_book_id': '9780451524935',
      };

      final path = LearningPath.fromJson(raw);
      expect(path.id, 'path-001');
      expect(path.title, 'Philosophy 101');
      expect(path.books.length, 2);
      expect(path.books[0].readingStatus, 'finished');
      expect(path.books[0].book?.title, 'Pride and Prejudice');
      expect(path.books[1].hasDueReview, isTrue);
      expect(path.progressPercent, 50);
      expect(path.totalReviewsDue, 1);
      expect(path.nextBookId, '9780451524935');

      final serialized = path.toJson();
      expect(serialized['title'], 'Philosophy 101');
      expect(serialized['total_books'], 2);
      expect(serialized['books'].length, 2);
    });

    test('copyWith updates properties cleanly', () {
      final path = LearningPath(
        id: 'p1',
        userId: 'u1',
        title: 'Original',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final updated = path.copyWith(title: 'Revised', progressPercent: 75);
      expect(updated.id, 'p1');
      expect(updated.title, 'Revised');
      expect(updated.progressPercent, 75);
    });
  });

  group('LearningPathProvider State Management Tests', () {
    late FakeLearningPathsApiService fakeApi;
    late LearningPathProvider provider;

    setUp(() {
      fakeApi = FakeLearningPathsApiService();
      provider = LearningPathProvider(apiService: fakeApi);
    });

    test('loadPaths loads paths and auto-selects first path', () async {
      await fakeApi.createLearningPath(title: 'Path Alpha', bookIds: ['9780141439518']);
      await fakeApi.createLearningPath(title: 'Path Beta');

      await provider.loadPaths();
      expect(provider.paths.length, 2);
      expect(provider.activePath?.title, 'Path Beta');
    });

    test('createPath adds path to state and sets active', () async {
      final created = await provider.createPath(
        title: 'New Path',
        category: 'Classics',
        bookIds: ['9780141439518'],
      );

      expect(created, isNotNull);
      expect(provider.paths.length, 1);
      expect(provider.activePath?.title, 'New Path');
    });

    test('addBook and removeBook mutate path books', () async {
      final created = await provider.createPath(title: 'Path 1');
      expect(created, isNotNull);

      final okAdd = await provider.addBook(created!.id, '9780141439518');
      expect(okAdd, isTrue);
      expect(provider.activePath?.books.length, 1);

      final okRem = await provider.removeBook(created.id, '9780141439518');
      expect(okRem, isTrue);
      expect(provider.activePath?.books.length, 0);
    });

    test('reorderBooks updates sequence order', () async {
      final created = await provider.createPath(
        title: 'Reorder Test',
        bookIds: ['b1', 'b2', 'b3'],
      );

      final ok = await provider.reorderBooks(created!.id, ['b3', 'b1', 'b2']);
      expect(ok, isTrue);
      final books = provider.activePath!.books;
      expect(books[0].bookId, 'b3');
      expect(books[1].bookId, 'b1');
      expect(books[2].bookId, 'b2');
    });

    test('deletePath removes from list and updates active path', () async {
      final p1 = await provider.createPath(title: 'P1');
      final p2 = await provider.createPath(title: 'P2');
      expect(provider.paths.length, 2);

      final ok = await provider.deletePath(p2!.id);
      expect(ok, isTrue);
      expect(provider.paths.length, 1);
      expect(provider.activePath?.id, p1!.id);
    });

    test('account isolation: updateUser cleans state on logout or switch', () async {
      fakeApi.currentUserId = 'user-a';
      provider.updateUser('user-a');
      await provider.createPath(title: 'User A Secret Path');
      expect(provider.paths.length, 1);

      // User logs out (null)
      provider.updateUser(null);
      expect(provider.paths.isEmpty, isTrue);
      expect(provider.activePath, isNull);

      // User B logs in
      fakeApi.currentUserId = 'user-b';
      provider.updateUser('user-b');
      await provider.loadPaths();
      expect(provider.paths.isEmpty, isTrue);
    });
  });
}

