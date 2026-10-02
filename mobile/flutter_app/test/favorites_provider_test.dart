import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/services/supabase_service.dart';

class FakeSupabaseService implements SupabaseService {
  final _favoritesStreamController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final List<Map<String, dynamic>> _mockDb = [];
  bool shouldFailAdd = false;
  bool shouldFailRemove = false;

  void pushStreamUpdate() {
    _favoritesStreamController.add(List.from(_mockDb));
  }

  void pushStreamError(Exception error) {
    _favoritesStreamController.addError(error);
  }

  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) {
    return _favoritesStreamController.stream;
  }

  @override
  Future<void> addFavorite({
    required String userId,
    required String bookId,
    required String title,
    required String author,
    required String? imageUrl,
  }) async {
    if (shouldFailAdd) throw Exception('Add failed');
    _mockDb.insert(0, {
      'id': 'db_id_$bookId',
      'user_id': userId,
      'book_id': bookId,
      'book_title': title,
      'book_author': author,
      'book_image_url': imageUrl,
      'added_at': DateTime.now().toIso8601String(),
    });
    pushStreamUpdate();
  }

  @override
  Future<void> removeFavorite(String userId, String bookId) async {
    if (shouldFailRemove) throw Exception('Remove failed');
    _mockDb.removeWhere((item) => item['book_id'] == bookId && item['user_id'] == userId);
    pushStreamUpdate();
  }

  // Dummy implementations for unrelated methods
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FavoritesProvider - Load', () {
    test('loadFavorites success: listen to stream and update state', () async {
      final svc = FakeSupabaseService();
      final provider = FavoritesProvider(svc);

      provider.loadFavorites('user-1');
      expect(provider.isLoading, true);

      // Simulate stream emitting data
      svc._mockDb.add({
        'id': '1',
        'user_id': 'user-1',
        'book_id': 'isbn-1',
        'book_title': 'Test Book',
        'book_image_url': '',
        'added_at': '2023-01-01T00:00:00.000Z',
      });
      svc.pushStreamUpdate();

      // Wait for stream to be processed
      await Future.delayed(Duration.zero);

      expect(provider.isLoading, false);
      expect(provider.favorites.length, 1);
      expect(provider.favorites.first.isbn13, 'isbn-1');
      expect(provider.isFavorite('isbn-1'), true);

      provider.dispose();
    });

    test('loadFavorites error: sets error state', () async {
      final svc = FakeSupabaseService();
      final provider = FavoritesProvider(svc);

      provider.loadFavorites('user-1');
      svc.pushStreamError(Exception('stream error'));

      await Future.delayed(Duration.zero);

      expect(provider.isLoading, false);
      expect(provider.error, isNotNull);
      expect(provider.favorites, isEmpty);

      provider.dispose();
    });
  });

  group('FavoritesProvider - Add/Remove', () {
    test('toggleFavorite adds book and optimistically updates', () async {
      final svc = FakeSupabaseService();
      final provider = FavoritesProvider(svc);
      provider.loadFavorites('user-1');

      final book = Book(
        isbn13: 'isbn-new',
        title: 'New Book',
        authors: 'Author',
        categories: '',
        description: '',
        thumbnail: '',
        averageRating: 0,
        ratingsCount: 0,
        publishedDate: '2023',
        pageCount: 100,
      );

      final future = provider.toggleFavorite(userId: 'user-1', book: book);

      // Before future completes, optimistic update should be visible
      expect(provider.isFavorite('isbn-new'), true);

      await future;
      await Future.delayed(Duration.zero); // wait for stream update

      expect(provider.favorites.length, 1);
      expect(provider.favorites.first.id, 'db_id_isbn-new'); // Real DB record arrived

      provider.dispose();
    });

    test('toggleFavorite failure: rollbacks optimistic update', () async {
      final svc = FakeSupabaseService();
      svc.shouldFailAdd = true;
      final provider = FavoritesProvider(svc);
      provider.loadFavorites('user-1');

      final book = Book(
        isbn13: 'isbn-new',
        title: 'New Book',
        authors: 'Author',
        categories: '',
        description: '',
        thumbnail: '',
        averageRating: 0,
        ratingsCount: 0,
        publishedDate: '2023',
        pageCount: 100,
      );

      await provider.toggleFavorite(userId: 'user-1', book: book);

      expect(provider.error, isNotNull);
      expect(provider.isFavorite('isbn-new'), false);

      provider.dispose();
    });
  });

  group('FavoritesProvider - Logout', () {
    test('clearFavorites clears list', () async {
      final svc = FakeSupabaseService();
      final provider = FavoritesProvider(svc);

      svc._mockDb.add({
        'id': '1',
        'user_id': 'user-1',
        'book_id': 'isbn-1',
        'book_title': 'Test',
        'book_image_url': '',
        'added_at': '2023-01-01T00:00:00.000Z',
      });
      provider.loadFavorites('user-1');
      svc.pushStreamUpdate();
      await Future.delayed(Duration.zero);
      expect(provider.favorites.length, 1);

      provider.clearFavorites();

      expect(provider.favorites, isEmpty);
      provider.dispose();
    });
  });
}
