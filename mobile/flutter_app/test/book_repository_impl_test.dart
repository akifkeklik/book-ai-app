import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:book_ai_app/services/supabase_service.dart';
import 'package:book_ai_app/data/repositories/book_repository_impl.dart';

// --- Fakes ---

class FakeApiService implements ApiService {
  List<Book> popularResult = [];
  Exception? popularError;

  Book? bookByIsbnResult;
  Exception? bookByIsbnError;

  @override
  Future<List<Book>> getPopularBooks({int limit = 2000}) async {
    if (popularError != null) throw popularError!;
    return popularResult;
  }

  @override
  Future<Book?> getBookByIsbn(String isbn) async {
    if (bookByIsbnError != null) throw bookByIsbnError!;
    return bookByIsbnResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupabaseService implements SupabaseService {
  List<Book> popularResult = [];
  Exception? popularError;

  Book? bookByIsbnResult;
  Exception? bookByIsbnError;

  @override
  Future<List<Book>> getPopularBooks({int limit = 50}) async {
    if (popularError != null) throw popularError!;
    return popularResult;
  }

  @override
  Future<Book?> getBookByIsbn(String isbn) async {
    if (bookByIsbnError != null) throw bookByIsbnError!;
    return bookByIsbnResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// --- Tests ---

void main() {
  group('BookRepositoryImpl - API/Supabase Fallback Behavior', () {
    test('getPopularBooks: returns Supabase result on success', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();

      supabase.popularResult = [
        const Book(isbn13: '1', title: 'Supabase Book', authors: 'A', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0)
      ];
      api.popularResult = [
        const Book(isbn13: '2', title: 'API Book', authors: 'B', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0)
      ];

      final repo = BookRepositoryImpl(api, supabase);
      final result = await repo.getPopularBooks();

      expect(result.first.title, 'Supabase Book');
    });

    test('getPopularBooks: falls back to API on Supabase error', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();

      supabase.popularError = Exception('Supabase is down');
      api.popularResult = [
        const Book(isbn13: '2', title: 'API Book', authors: 'B', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0)
      ];

      final repo = BookRepositoryImpl(api, supabase);
      final result = await repo.getPopularBooks();

      expect(result.first.title, 'API Book');
    });

    test('getBookByIsbn: falls back to API if Supabase returns null', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();

      supabase.bookByIsbnResult = null;
      api.bookByIsbnResult = const Book(isbn13: '123', title: 'API Book Details', authors: 'B', categories: '', description: '', thumbnail: '', averageRating: 0, ratingsCount: 0, publishedDate: '', pageCount: 0);

      final repo = BookRepositoryImpl(api, supabase);
      final result = await repo.getBookByIsbn('123');

      expect(result?.title, 'API Book Details');
    });

    test('getBookByIsbn: propagates error if API fails during fallback', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();

      supabase.bookByIsbnResult = null;
      api.bookByIsbnError = Exception('API timeout');

      final repo = BookRepositoryImpl(api, supabase);

      expect(
        () => repo.getBookByIsbn('123'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
