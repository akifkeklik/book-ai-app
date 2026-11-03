import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:book_ai_app/services/supabase_service.dart';
import 'package:book_ai_app/data/repositories/book_repository_impl.dart';

// --- Fakes ---

class FakeBox implements Box {
  final Map<dynamic, dynamic> store = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => store[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    store[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    store.remove(key);
  }

  @override
  bool containsKey(dynamic key) => store.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApiService implements ApiService {
  List<Book> popularResult = [];
  Exception? popularError;

  Book? bookByIsbnResult;
  Exception? bookByIsbnError;

  Map<String, dynamic>? userPreferencesResult;
  Exception? userPreferencesError;
  bool updateUserPreferencesCalled = false;

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
  Future<Map<String, dynamic>?> getUserPreferences({String? userId}) async {
    if (userPreferencesError != null) throw userPreferencesError!;
    return userPreferencesResult;
  }

  @override
  Future<bool> updateUserPreferences({
    required String userId,
    required List<String> genres,
    List<String>? authors,
  }) async {
    updateUserPreferencesCalled = true;
    return true;
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

  String? userInteractionResult;
  Exception? userInteractionError;

  @override
  Future<String?> getUserInteraction(String userId, String bookId) async {
    if (userInteractionError != null) throw userInteractionError!;
    return userInteractionResult;
  }

  Map<String, dynamic>? userProfileResult;
  Exception? userProfileError;
  bool upsertUserProfileCalled = false;

  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    if (userProfileError != null) throw userProfileError!;
    return userProfileResult;
  }

  @override
  Future<void> upsertUserProfile({
    required String userId,
    required List<String> preferredGenres,
    required int readingFrequency,
    required List<String> preferredAuthors,
    required String preferredVibe,
  }) async {
    upsertUserProfileCalled = true;
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

    test('getUserInteraction: delegates to SupabaseService and returns active status', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();
      supabase.userInteractionResult = 'reading';

      final repo = BookRepositoryImpl(api, supabase);
      final result = await repo.getUserInteraction('user-1', '9780140449136');

      expect(result, 'reading');
    });

    test('getUserInteraction: returns null if user has no interaction for book', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();
      supabase.userInteractionResult = null;

      final repo = BookRepositoryImpl(api, supabase);
      final result = await repo.getUserInteraction('user-1', '9780140449136');

      expect(result, isNull);
    });
  });

  group('BookRepositoryImpl - Offline Hive Profile Caching and Account Isolation', () {
    test('getUserProfile & upsertUserProfile: reject empty or whitespace userId', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();
      final box = FakeBox();
      final repo = BookRepositoryImpl(api, supabase, box);

      final profile = await repo.getUserProfile('');
      expect(profile, isNull);

      final profileWhitespace = await repo.getUserProfile('   ');
      expect(profileWhitespace, isNull);

      await repo.upsertUserProfile(
        userId: '   ',
        preferredGenres: ['Sci-Fi'],
        readingFrequency: 3,
        preferredAuthors: ['Asimov'],
        preferredVibe: 'intellectual',
      );
      expect(box.store.isEmpty, true);
      expect(supabase.upsertUserProfileCalled, false);
      expect(api.updateUserPreferencesCalled, false);
    });

    test('getUserProfile: marks remote response with is_from_cache: false and writes to box', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();
      final box = FakeBox();
      final repo = BookRepositoryImpl(api, supabase, box);

      supabase.userProfileResult = {
        'user_id': 'user-123',
        'preferred_genres': ['Classics'],
        'reading_frequency': 2,
        'preferred_authors': ['Austen'],
        'preferred_vibe': 'reflective',
      };

      final res = await repo.getUserProfile('user-123');
      expect(res, isNotNull);
      expect(res!['user_id'], 'user-123');
      expect(res['is_from_cache'], false);

      // Verify cached into box with account-scoped key
      expect(box.containsKey('user_profile_user-123'), true);
      final cachedJson = box.get('user_profile_user-123');
      final decoded = jsonDecode(cachedJson);
      expect(decoded['preferred_genres'], ['Classics']);
    });

    test('getUserProfile: marks fallback offline cache with is_from_cache: true when remote fails', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();
      final box = FakeBox();
      final repo = BookRepositoryImpl(api, supabase, box);

      // Pre-seed offline cache for user-456
      box.store['user_profile_user-456'] = jsonEncode({
        'user_id': 'user-456',
        'preferred_genres': ['Fantasy'],
        'reading_frequency': 1,
        'preferred_authors': ['Tolkien'],
        'preferred_vibe': 'epic',
      });

      // Simulate remote network failure
      supabase.userProfileError = Exception('Supabase offline');
      api.userPreferencesError = Exception('Flask API timeout');

      final res = await repo.getUserProfile('user-456');
      expect(res, isNotNull);
      expect(res!['user_id'], 'user-456');
      expect(res['is_from_cache'], true);
      expect(res['preferred_genres'], ['Fantasy']);
    });

    test('clearUserCache: deletes account-scoped profile and favorites keys', () async {
      final api = FakeApiService();
      final supabase = FakeSupabaseService();
      final box = FakeBox();
      final repo = BookRepositoryImpl(api, supabase, box);

      box.store['user_profile_user-target'] = '{"genres":["Fiction"]}';
      box.store['favorites_cache_user-target'] = '["9781234"]';
      box.store['user_profile_user-other'] = '{"genres":["Mystery"]}';

      repo.clearUserCache('user-target');

      expect(box.containsKey('user_profile_user-target'), false);
      expect(box.containsKey('favorites_cache_user-target'), false);
      // Other user cache remains untouched
      expect(box.containsKey('user_profile_user-other'), true);
    });
  });
}
