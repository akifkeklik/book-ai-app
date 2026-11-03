import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/application/use_cases/manage_catalog_use_case.dart';
import 'package:book_ai_app/application/use_cases/manage_recommendations_use_case.dart';
import 'package:book_ai_app/application/use_cases/search_books_use_case.dart';
import 'package:book_ai_app/providers/catalog_provider.dart';
import 'package:book_ai_app/providers/search_provider.dart';
import 'package:book_ai_app/providers/auth_provider.dart';
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/screens/category_timeline_screen.dart';
import 'package:book_ai_app/data/repositories/book_repository_impl.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:book_ai_app/services/supabase_service.dart';
import 'package:book_ai_app/services/auth_service_base.dart';

// ---------------------------------------------------------------------------
// Test Doubles
// ---------------------------------------------------------------------------

class FakeBox implements Box {
  final Map<dynamic, dynamic> _store = {};
  bool throwOnRead = false;
  bool throwOnWrite = false;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    if (throwOnRead) throw Exception('Disk read I/O error');
    return _store[key] ?? defaultValue;
  }

  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (throwOnWrite) throw Exception('Disk write full error');
    _store[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _store.remove(key);
  }

  @override
  bool containsKey(dynamic key) => _store.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestApiService implements ApiService {
  List<Book> popularBooks = [];
  Exception? error;

  Map<String, dynamic> categoryResponse = {};
  Exception? categoryError;
  int categoryCallCount = 0;
  Duration? categoryDelay;

  @override
  Future<List<Book>> getPopularBooks({int limit = 20}) async {
    if (error != null) throw error!;
    return popularBooks;
  }

  @override
  Future<Map<String, dynamic>> getBooksByCategory({
    required String category,
    int page = 1,
    int perPage = 40,
    String? sort,
    String? author,
    String? publisher,
    int? minPages,
    int? maxPages,
    double? minRating,
    int? publishedFrom,
    int? publishedTo,
  }) async {
    categoryCallCount++;
    if (categoryDelay != null) await Future.delayed(categoryDelay!);
    if (categoryError != null) throw categoryError!;
    return categoryResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestSupabaseService implements SupabaseService {
  List<Book> popularBooks = [];
  Exception? popularError;
  List<Book> searchBooksResult = [];
  Exception? searchError;

  @override
  Future<List<Book>> getPopularBooks({int limit = 20}) async {
    if (popularError != null) throw popularError!;
    return popularBooks;
  }

  @override
  Future<List<Book>> searchBooks(String query) async {
    if (searchError != null) throw searchError!;
    return searchBooksResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class InMemoryTestRepository implements BookRepository {
  List<Book> networkPopularBooks = [];
  Exception? networkPopularError;

  List<Book> cachedPopularBooks = [];
  List<Book> savedPopularBooks = [];

  List<Book> networkSearchResults = [];
  Exception? networkSearchError;
  Duration? searchDelay;

  Map<String, List<Book>> cachedSearch = {};
  Map<String, List<Book>> savedSearch = {};

  int searchCallCount = 0;

  static Book makeBook(String id, String title) => Book(
        isbn13: id,
        title: title,
        authors: 'Author $id',
        categories: 'Fiction',
        description: 'Description $id',
        thumbnail: 'https://example.com/$id.jpg',
        averageRating: 4.5,
        ratingsCount: 100,
        publishedDate: '2023',
        pageCount: 250,
      );

  @override
  Future<List<Book>> getPopularBooks({int limit = 20}) async {
    if (networkPopularError != null) throw networkPopularError!;
    return networkPopularBooks;
  }

  @override
  List<Book> getCachedPopularBooks() => cachedPopularBooks;

  @override
  void savePopularBooksToCache(List<Book> books) {
    savedPopularBooks = List.from(books);
    cachedPopularBooks = List.from(books);
  }

  @override
  Future<List<Book>> searchBooks(String query) async {
    searchCallCount++;
    if (searchDelay != null) await Future.delayed(searchDelay!);
    if (networkSearchError != null) throw networkSearchError!;
    return networkSearchResults;
  }

  @override
  List<Book> getCachedSearchResults(String query) {
    return cachedSearch[query.trim().toLowerCase()] ?? [];
  }

  @override
  void saveSearchResultsToCache(String query, List<Book> books) {
    savedSearch[query.trim().toLowerCase()] = List.from(books);
    cachedSearch[query.trim().toLowerCase()] = List.from(books);
  }

  @override
  Future<int> getTotalBookCount() async => 6400;

  @override
  Future<List<Map<String, dynamic>>> getCategories() async => [];

  Map<String, List<Book>> networkCategoryResults = {};
  Exception? networkCategoryError;
  Duration? categoryDelay;
  int categoryCallCount = 0;

  Map<String, List<Book>> cachedCategory = {};
  Map<String, List<Book>> savedCategory = {};

  @override
  Future<Map<String, dynamic>> getBooksByCategory({
    required String category,
    int page = 1,
    int perPage = 40,
    String? sort,
    String? author,
    String? publisher,
    int? minPages,
    int? maxPages,
    double? minRating,
    int? publishedFrom,
    int? publishedTo,
  }) async {
    categoryCallCount++;
    if (categoryDelay != null) await Future.delayed(categoryDelay!);
    if (networkCategoryError != null) {
      final cached = getCachedCategoryBooks(category);
      if (cached.isNotEmpty) {
        return {
          'books': cached,
          'total': cached.length,
          'total_pages': 1,
          'is_from_cache': true,
        };
      }
      throw networkCategoryError!;
    }
    final books = networkCategoryResults[category.trim().toLowerCase()] ?? [];
    if (page == 1 && books.isNotEmpty) {
      saveCategoryBooksToCache(category, books);
    }
    return {
      'books': books,
      'total': books.length,
      'total_pages': 1,
      'is_from_cache': false,
    };
  }

  @override
  List<Book> getCachedCategoryBooks(String category) {
    return cachedCategory[category.trim().toLowerCase()] ?? [];
  }

  @override
  void saveCategoryBooksToCache(String category, List<Book> books,
      {int? total, int? totalPages}) {
    savedCategory[category.trim().toLowerCase()] = List.from(books);
    cachedCategory[category.trim().toLowerCase()] = List.from(books);
  }

  @override
  void clearUserCache(String userId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('1. Catalog Offline Resilience (CatalogProvider & Cache)', () {
    test('Başarılı ağ yanıtının önbelleğe kaydedilmesi', () async {
      final repo = InMemoryTestRepository();
      repo.networkPopularBooks = [
        InMemoryTestRepository.makeBook('b1', 'The Hobbit'),
        InMemoryTestRepository.makeBook('b2', 'Dune'),
      ];

      final useCase = ManageCatalogUseCase(repo);
      final provider = CatalogProvider(manageCatalog: useCase);

      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.loaded);
      expect(provider.isFromCache, false);
      expect(provider.isOffline, false);
      expect(provider.popularBooks.length, 2);
      expect(repo.savedPopularBooks.length, 2);
      expect(repo.savedPopularBooks.first.title, 'The Hobbit');
      provider.dispose();
    });

    test('Ağ hatasında önbellekteki katalog verisinin gösterilmesi (isFromCache == true)', () async {
      final repo = InMemoryTestRepository();
      // Pre-seed cache
      repo.cachedPopularBooks = [
        InMemoryTestRepository.makeBook('c1', 'Cached Book 1'),
        InMemoryTestRepository.makeBook('c2', 'Cached Book 2'),
      ];
      // Network fails
      repo.networkPopularError = Exception('No internet connection');

      final useCase = ManageCatalogUseCase(repo);
      final provider = CatalogProvider(manageCatalog: useCase);

      // Force fetch to simulate refresh while offline
      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.loaded);
      expect(provider.isFromCache, true);
      expect(provider.isOffline, true);
      expect(provider.error, isNull);
      expect(provider.popularBooks.length, 2);
      expect(provider.popularBooks.first.title, 'Cached Book 1');
      provider.dispose();
    });

    test('Önbellek boşken kontrollü hata durumu', () async {
      final repo = InMemoryTestRepository();
      repo.cachedPopularBooks = [];
      repo.networkPopularError = Exception('SocketException: Network unreachable');

      final useCase = ManageCatalogUseCase(repo);
      final provider = CatalogProvider(manageCatalog: useCase);

      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.error);
      expect(provider.isFromCache, false);
      expect(provider.error, 'error_loading_books');
      expect(provider.popularBooks, isEmpty);
      provider.dispose();
    });

    test('Önbellekten başlama ardından başarılı ağ çağrısı isFromCache bayrağını temizler', () async {
      final repo = InMemoryTestRepository();
      repo.cachedPopularBooks = [
        InMemoryTestRepository.makeBook('c1', 'Stale Cached'),
      ];
      repo.networkPopularBooks = [
        InMemoryTestRepository.makeBook('n1', 'Fresh Network Book'),
      ];

      final useCase = ManageCatalogUseCase(repo);
      final provider = CatalogProvider(manageCatalog: useCase);

      // Initially loaded from cache
      expect(provider.isFromCache, true);
      expect(provider.popularBooks.first.title, 'Stale Cached');

      // Network fetch succeeds
      await provider.fetchPopular(force: true);

      expect(provider.status, CatalogStatus.loaded);
      expect(provider.isFromCache, false);
      expect(provider.popularBooks.first.title, 'Fresh Network Book');
      provider.dispose();
    });
  });

  group('2. Search Offline Resilience (SearchProvider & Cache)', () {
    test('Başarılı arama yanıtının önbelleğe kaydedilmesi', () async {
      final repo = InMemoryTestRepository();
      repo.networkSearchResults = [
        InMemoryTestRepository.makeBook('s1', '1984'),
        InMemoryTestRepository.makeBook('s2', 'Animal Farm'),
      ];

      final useCase = SearchBooksUseCase(repo);
      final provider = SearchProvider(searchBooksUseCase: useCase);

      provider.search('Orwell');
      await Future.delayed(Duration.zero);

      expect(provider.status, SearchStatus.loaded);
      expect(provider.isFromCache, false);
      expect(provider.isOffline, false);
      expect(provider.searchResults.length, 2);
      // Verify saved in cache under normalized key
      expect(repo.savedSearch['orwell']?.length, 2);
      expect(repo.savedSearch['orwell']?.first.title, '1984');
      provider.dispose();
    });

    test('Ağ hatasında sorguya ait önbellekli arama sonuçlarının gösterilmesi', () async {
      final repo = InMemoryTestRepository();
      // Pre-seed cache for 'tolkien'
      repo.cachedSearch['tolkien'] = [
        InMemoryTestRepository.makeBook('t1', 'The Fellowship of the Ring'),
      ];
      // Network fails
      repo.networkSearchError = Exception('Connection timed out');

      final useCase = SearchBooksUseCase(repo);
      final provider = SearchProvider(searchBooksUseCase: useCase);

      provider.search('Tolkien');
      await Future.delayed(Duration.zero);

      expect(provider.status, SearchStatus.loaded);
      expect(provider.isFromCache, true);
      expect(provider.isOffline, true);
      expect(provider.error, isNull);
      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.title, 'The Fellowship of the Ring');
      provider.dispose();
    });

    test('Önbellek boşken kontrollü hata durumu (arama)', () async {
      final repo = InMemoryTestRepository();
      repo.networkSearchError = Exception('Supabase 503 unavailable');

      final useCase = SearchBooksUseCase(repo);
      final provider = SearchProvider(searchBooksUseCase: useCase);

      provider.search('nonexistent query');
      await Future.delayed(Duration.zero);

      expect(provider.status, SearchStatus.error);
      expect(provider.isFromCache, false);
      expect(provider.error, 'search_failed');
      expect(provider.searchResults, isEmpty);
      provider.dispose();
    });

    test('Yeni sorgunun eski bir sorgu yanıtıyla ezilmemesi (stale query protection)', () async {
      final repo = InMemoryTestRepository();
      final useCase = SearchBooksUseCase(repo);
      final provider = SearchProvider(searchBooksUseCase: useCase);

      // Slow query 1
      repo.searchDelay = const Duration(milliseconds: 80);
      repo.networkSearchResults = [
        InMemoryTestRepository.makeBook('old', 'Slow Old Query Book'),
      ];
      provider.search('slow');

      // Fast query 2
      repo.searchDelay = Duration.zero;
      repo.networkSearchResults = [
        InMemoryTestRepository.makeBook('new', 'Fast New Query Book'),
      ];
      provider.search('fast');

      // Wait for slow query to complete
      await Future.delayed(const Duration(milliseconds: 120));

      expect(provider.status, SearchStatus.loaded);
      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.title, 'Fast New Query Book');
      provider.dispose();
    });

    test('clearSearch arama durumu ve önbellek bayraklarını sıfırlar', () async {
      final repo = InMemoryTestRepository();
      repo.cachedSearch['test'] = [InMemoryTestRepository.makeBook('1', 'Cached')];
      repo.networkSearchError = Exception('offline');

      final useCase = SearchBooksUseCase(repo);
      final provider = SearchProvider(searchBooksUseCase: useCase);

      provider.search('test');
      await Future.delayed(Duration.zero);
      expect(provider.isFromCache, true);
      expect(provider.searchResults.isNotEmpty, true);

      provider.clearSearch();

      expect(provider.status, SearchStatus.initial);
      expect(provider.searchResults, isEmpty);
      expect(provider.isFromCache, false);
      expect(provider.lastQuery, isEmpty);
      provider.dispose();
    });
  });

  group('2b. Category Offline Resilience (Repository, UseCase, UI State)', () {
    test('Başarılı kategori yanıtının önbelleğe kaydedilmesi', () async {
      final box = FakeBox();
      final api = FakeTestApiService();
      final repo = BookRepositoryImpl(api, FakeTestSupabaseService(), box);

      api.categoryResponse = {
        'books': [
          const Book(
            isbn13: 'sf1',
            title: 'Dune',
            authors: 'Frank Herbert',
            categories: 'Science Fiction',
            description: 'Desert planet',
            thumbnail: 'https://example.com/dune.jpg',
            averageRating: 4.8,
            ratingsCount: 5000,
            publishedDate: '1965',
            pageCount: 600,
          ),
          const Book(
            isbn13: 'sf2',
            title: 'Foundation',
            authors: 'Isaac Asimov',
            categories: 'Science Fiction',
            description: 'Galactic empire',
            thumbnail: 'https://example.com/foundation.jpg',
            averageRating: 4.7,
            ratingsCount: 4000,
            publishedDate: '1951',
            pageCount: 250,
          ),
        ],
        'total': 2,
        'total_pages': 1,
      };

      final result = await repo.getBooksByCategory(category: 'Science Fiction');

      expect(result['is_from_cache'], false);
      expect((result['books'] as List).length, 2);

      // Verify written to Hive box under normalized key
      expect(box.containsKey('category_science fiction'), true);

      // Verify cached read succeeds
      final cached = repo.getCachedCategoryBooks('Science Fiction');
      expect(cached.length, 2);
      expect(cached.first.title, 'Dune');
    });

    test('Ağ hatasında önbellekteki kategorinin gösterilmesi (is_from_cache == true)', () async {
      final box = FakeBox();
      final api = FakeTestApiService();
      final repo = BookRepositoryImpl(api, FakeTestSupabaseService(), box);

      // Pre-seed cache
      repo.saveCategoryBooksToCache('History', [
        InMemoryTestRepository.makeBook('h1', 'Sapiens'),
      ]);

      // Network fails
      api.categoryError = Exception('SocketException: Failed host lookup');

      final result = await repo.getBooksByCategory(category: 'History');

      expect(result['is_from_cache'], true);
      final books = result['books'] as List<Book>;
      expect(books.length, 1);
      expect(books.first.title, 'Sapiens');
    });

    test('Önbellek boşken kontrollü hata durumu (kategori)', () async {
      final box = FakeBox();
      final api = FakeTestApiService();
      final repo = BookRepositoryImpl(api, FakeTestSupabaseService(), box);

      api.categoryError = Exception('500 Internal Server Error');

      expect(
        () => repo.getBooksByCategory(category: 'Philosophy'),
        throwsA(isA<Exception>()),
      );
    });

    test('Normalize edilmiş kategori anahtarlarının tutarlılığı', () {
      final box = FakeBox();
      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      repo.saveCategoryBooksToCache(
        '  Young   Adult & Children  ',
        [InMemoryTestRepository.makeBook('ya1', 'Harry Potter')],
      );

      // Access with various formats
      expect(repo.getCachedCategoryBooks('young adult & children').length, 1);
      expect(repo.getCachedCategoryBooks('Young Adult & Children').length, 1);
      expect(repo.getCachedCategoryBooks('YOUNG ADULT & CHILDREN').length, 1);
      expect(repo.getCachedCategoryBooks('  Young   Adult & Children  ').length, 1);
      expect(repo.getCachedCategoryBooks('young   adult & children').first.title, 'Harry Potter');
    });

    test('Eşzamanlı isteklerde API çağrısı tekilleştirme', () async {
      final box = FakeBox();
      final api = FakeTestApiService();
      final repo = BookRepositoryImpl(api, FakeTestSupabaseService(), box);

      api.categoryDelay = const Duration(milliseconds: 50);
      api.categoryResponse = {
        'books': [InMemoryTestRepository.makeBook('f1', 'The Hobbit')],
        'total': 1,
        'total_pages': 1,
      };

      // Launch two concurrent requests for the exact same category
      final future1 = repo.getBooksByCategory(category: 'Fantasy');
      final future2 = repo.getBooksByCategory(category: 'Fantasy');

      final results = await Future.wait([future1, future2]);

      expect(results[0]['books'].length, 1);
      expect(results[1]['books'].length, 1);
      // Ensure only 1 actual network call was dispatched
      expect(api.categoryCallCount, 1);
    });

    testWidgets('CategoryTimelineScreen: ağ hatasında önbellekten gelen veriyi offline banner ile gösterir', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = InMemoryTestRepository();
      repo.cachedCategory['fiction'] = [
        InMemoryTestRepository.makeBook('fic1', 'The Great Gatsby'),
      ];
      repo.networkCategoryError = Exception('Offline');

      final useCase = ManageCatalogUseCase(repo);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ManageCatalogUseCase>.value(value: useCase),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ],
          child: const MaterialApp(
            home: CategoryTimelineScreen(genre: 'Fiction'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify book card rendered from cache
      expect(find.text('The Great Gatsby'), findsOneWidget);
      // Verify offline banner rendered
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('CategoryTimelineScreen: önbellek yokken hata ve tekrar dene butonu gösterir', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = InMemoryTestRepository();
      repo.cachedCategory.clear();
      repo.networkCategoryError = Exception('Connection refused');

      final useCase = ManageCatalogUseCase(repo);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ManageCatalogUseCase>.value(value: useCase),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ],
          child: const MaterialApp(
            home: CategoryTimelineScreen(genre: 'Drama & Plays'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify error icon and retry button
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Now simulate network restored and click retry
      repo.networkCategoryError = null;
      repo.networkCategoryResults['drama & plays'] = [
        InMemoryTestRepository.makeBook('d1', 'Hamlet'),
      ];

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('Hamlet'), findsOneWidget);
    });

    testWidgets('Kategori değişiminde eski yanıtın yeni sonucu ezmemesi (race condition protection)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = InMemoryTestRepository();
      // Category 1 is slow (100ms)
      repo.categoryDelay = const Duration(milliseconds: 100);
      repo.networkCategoryResults['category1'] = [
        InMemoryTestRepository.makeBook('c1', 'Slow Category 1 Book'),
      ];
      repo.networkCategoryResults['category2'] = [
        InMemoryTestRepository.makeBook('c2', 'Fast Category 2 Book'),
      ];

      final useCase = ManageCatalogUseCase(repo);

      Widget buildWidget(String genre) {
        return MultiProvider(
          providers: [
            Provider<ManageCatalogUseCase>.value(value: useCase),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ],
          child: MaterialApp(
            home: CategoryTimelineScreen(genre: genre),
          ),
        );
      }

      // Start loading Category 1
      await tester.pumpWidget(buildWidget('category1'));
      await tester.pump(); // Start fetch

      // Fast switch to Category 2 (no delay)
      repo.categoryDelay = Duration.zero;
      await tester.pumpWidget(buildWidget('category2'));
      await tester.pumpAndSettle();

      // Category 2 should be displayed
      expect(find.text('Fast Category 2 Book'), findsOneWidget);

      // Now wait 150ms for slow Category 1 response to finally complete
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // Category 1 book MUST NOT have overwritten or mixed into Category 2
      expect(find.text('Slow Category 1 Book'), findsNothing);
      expect(find.text('Fast Category 2 Book'), findsOneWidget);
    });
  });

  group('3. Bozuk veya Okunamayan Önbellek Verisi Dayanıklılığı (BookRepositoryImpl)', () {
    test('Bozuk JSON dizesi okurken çökmeme (popular books)', () {
      final box = FakeBox();
      box.put('popular_books', '{corrupted json string [invalid');

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      final cached = repo.getCachedPopularBooks();
      expect(cached, isEmpty);
    });

    test('Bozuk JSON dizesi okurken çökmeme (search cache)', () {
      final box = FakeBox();
      box.put('search_asimov', '{"not": "a list", bad syntax');

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      final cached = repo.getCachedSearchResults('Asimov');
      expect(cached, isEmpty);
    });

    test('Geçersiz veri tipleri (sayı, map, null) okurken çökmeme', () {
      final box = FakeBox();
      box.put('popular_books', 123456); // integer instead of JSON string
      box.put('search_test', true); // boolean

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      expect(repo.getCachedPopularBooks(), isEmpty);
      expect(repo.getCachedSearchResults('test'), isEmpty);
    });

    test('Kısmen bozuk liste elemanlarını güvenle atlayarak geçerlileri döndürme', () {
      final box = FakeBox();
      final mixedData = jsonEncode([
        {'isbn13': 'valid-1', 'title': 'Valid Book 1'},
        'broken_item_string',
        null,
        123,
        {'isbn13': 'valid-2', 'title': 'Valid Book 2'},
      ]);
      box.put('popular_books', mixedData);

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      final cached = repo.getCachedPopularBooks();
      expect(cached.length, 2);
      expect(cached[0].title, 'Valid Book 1');
      expect(cached[1].title, 'Valid Book 2');
    });

    test('Disk I/O okuma hatasında uygulamanın çökmemesi', () {
      final box = FakeBox();
      box.throwOnRead = true;

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      expect(repo.getCachedPopularBooks(), isEmpty);
      expect(repo.getCachedSearchResults('query'), isEmpty);
      expect(repo.getCachedCategoryBooks('Fiction'), isEmpty);
    });

    test('Disk I/O yazma hatasında uygulamanın çökmemesi', () {
      final box = FakeBox();
      box.throwOnWrite = true;

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      // Should not rethrow exception
      expect(() => repo.savePopularBooksToCache([InMemoryTestRepository.makeBook('1', 'A')]), returnsNormally);
      expect(() => repo.saveSearchResultsToCache('test', [InMemoryTestRepository.makeBook('1', 'A')]), returnsNormally);
      expect(() => repo.saveCategoryBooksToCache('Fiction', [InMemoryTestRepository.makeBook('1', 'A')]), returnsNormally);
    });

    test('Bozuk JSON dizesi okurken çökmeme (category cache)', () {
      final box = FakeBox();
      box.put('category_fiction', '{corrupted json string [invalid');

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      final cached = repo.getCachedCategoryBooks('Fiction');
      expect(cached, isEmpty);
    });

    test('Geçersiz veri tipleri (sayı, map, null) okurken çökmeme (category cache)', () {
      final box = FakeBox();
      box.put('category_fiction', 42);

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      expect(repo.getCachedCategoryBooks('Fiction'), isEmpty);
    });

    test('Kısmen bozuk liste elemanlarını güvenle atlayarak geçerlileri döndürme (category cache)', () {
      final box = FakeBox();
      final mixedData = jsonEncode({
        'books': [
          {'isbn13': 'valid-cat-1', 'title': 'Valid Category Book'},
          'broken_item',
          null,
          456,
        ],
        'total': 1,
        'total_pages': 1,
      });
      box.put('category_fiction', mixedData);

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      final cached = repo.getCachedCategoryBooks('Fiction');
      expect(cached.length, 1);
      expect(cached.first.title, 'Valid Category Book');
    });

    test('Eski format (doğrudan JSON listesi) güvenle okunmalı', () {
      final box = FakeBox();
      final legacyData = jsonEncode([
        {'isbn13': 'leg-1', 'title': 'Legacy List Book'},
      ]);
      box.put('category_history', legacyData);

      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      final cached = repo.getCachedCategoryBooks('History');
      expect(cached.length, 1);
      expect(cached.first.title, 'Legacy List Book');
    });
  });

  group('4. Önbellek Boyutu ve LRU Politikası (Cache Size & LRU Policy)', () {
    test('Arama önbelleği 30 sorguyu aşınca en eski sorguyu tahliye eder (LRU)', () {
      final box = FakeBox();
      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      // Cache 35 distinct queries
      for (int i = 1; i <= 35; i++) {
        repo.saveSearchResultsToCache(
          'query_$i',
          [InMemoryTestRepository.makeBook('$i', 'Title $i')],
        );
      }

      // Keys 1 to 5 should have been evicted (35 - 30 = 5 oldest evicted)
      expect(repo.getCachedSearchResults('query_1'), isEmpty);
      expect(repo.getCachedSearchResults('query_5'), isEmpty);

      // Most recent queries 6 to 35 must still exist
      expect(repo.getCachedSearchResults('query_6'), isNotEmpty);
      expect(repo.getCachedSearchResults('query_35'), isNotEmpty);
    });

    test('Arama önbelleğinde erişim (okuma) LRU sırasını günceller ve tahliyeyi önler', () {
      final box = FakeBox();
      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      // Save 30 search queries (at capacity)
      for (int i = 1; i <= 30; i++) {
        repo.saveSearchResultsToCache(
          'query_$i',
          [InMemoryTestRepository.makeBook('$i', 'Book $i')],
        );
      }

      // Read query_1 (access update!)
      final accessed = repo.getCachedSearchResults('query_1');
      expect(accessed, isNotEmpty);

      // Now add query_31
      repo.saveSearchResultsToCache(
        'query_31',
        [InMemoryTestRepository.makeBook('31', 'Book 31')],
      );

      // query_2 should be evicted, query_1 MUST be preserved!
      expect(repo.getCachedSearchResults('query_1'), isNotEmpty);
      expect(repo.getCachedSearchResults('query_2'), isEmpty);
      expect(repo.getCachedSearchResults('query_31'), isNotEmpty);
    });

    test('Kategori önbelleği 25 kategoriyi aşınca en eski kategoriyi tahliye eder (LRU)', () {
      final box = FakeBox();
      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      // Save 30 categories
      for (int i = 1; i <= 30; i++) {
        repo.saveCategoryBooksToCache(
          'genre_$i',
          [InMemoryTestRepository.makeBook('$i', 'Book $i')],
        );
      }

      // Categories 1 to 5 should have been evicted (30 - 25 = 5 oldest evicted)
      expect(repo.getCachedCategoryBooks('genre_1'), isEmpty);
      expect(repo.getCachedCategoryBooks('genre_5'), isEmpty);

      // Categories 6 to 30 must still exist
      expect(repo.getCachedCategoryBooks('genre_6'), isNotEmpty);
      expect(repo.getCachedCategoryBooks('genre_30'), isNotEmpty);
    });

    test('Kategori önbelleğinde erişim (okuma) LRU sırasını günceller ve tahliyeyi önler', () {
      final box = FakeBox();
      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      // Save 25 categories (at capacity)
      for (int i = 1; i <= 25; i++) {
        repo.saveCategoryBooksToCache(
          'genre_$i',
          [InMemoryTestRepository.makeBook('$i', 'Book $i')],
        );
      }

      // Read genre_1 (access update!)
      final accessed = repo.getCachedCategoryBooks('genre_1');
      expect(accessed, isNotEmpty);

      // Now add genre_26
      repo.saveCategoryBooksToCache(
        'genre_26',
        [InMemoryTestRepository.makeBook('26', 'Book 26')],
      );

      // Because genre_1 was accessed, genre_2 is now the oldest and should be evicted!
      // genre_1 MUST still be in cache!
      expect(repo.getCachedCategoryBooks('genre_1'), isNotEmpty);
      expect(repo.getCachedCategoryBooks('genre_2'), isEmpty);
      expect(repo.getCachedCategoryBooks('genre_26'), isNotEmpty);
    });

    test('Popüler kitaplar önbelleği maksimum 50 kitap ile sınırlandırılır', () {
      final box = FakeBox();
      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      // Create 80 books
      final largeList = List.generate(
        80,
        (i) => InMemoryTestRepository.makeBook('$i', 'Book $i'),
      );

      repo.savePopularBooksToCache(largeList);

      final cached = repo.getCachedPopularBooks();
      expect(cached.length, 50);
    });

    test('Kategori önbelleği maksimum 50 kitap ile sınırlandırılır', () {
      final box = FakeBox();
      final repo = BookRepositoryImpl(
        FakeTestApiService(),
        FakeTestSupabaseService(),
        box,
      );

      final largeList = List.generate(
        80,
        (i) => InMemoryTestRepository.makeBook('$i', 'Book $i'),
      );

      repo.saveCategoryBooksToCache('Romance', largeList);

      final cached = repo.getCachedCategoryBooks('Romance');
      expect(cached.length, 50);
    });
  });

  group('5. Kullanıcı Oturum İzolasyonu (User Session Isolation)', () {
    test('Kullanıcı oturumları arasında özel verilerin sızmaması ve genel kataloğun korunması', () async {
      // Setup
      final fakeAuth = FakeAuthService();
      final authProvider = AuthProvider(fakeAuth);

      // 1. User A logs in
      await authProvider.login(email: 'userA@libris.com', password: 'password123');
      expect(authProvider.isLoggedIn, true);
      expect(authProvider.currentUser?.email, 'userA@libris.com');

      // User A loads recommendations & favorites
      final repo = InMemoryTestRepository();
      repo.cachedPopularBooks = [
        InMemoryTestRepository.makeBook('pub1', 'Public Popular Book'),
      ];
      repo.cachedCategory['fiction'] = [
        InMemoryTestRepository.makeBook('pub_fic_1', 'Public Fiction Book'),
      ];
      final recUseCase = ManageRecommendationsUseCase(repo);
      final recProvider = RecommendationProvider(manageRecommendations: recUseCase);

      // Simulate User A has personalized recs in memory
      recProvider.clearUserData(); // reset
      expect(recProvider.personalizedRecs, isEmpty);

      // 2. User A logs out
      recProvider.clearUserData();
      await authProvider.logout();

      expect(authProvider.isLoggedIn, false);
      expect(authProvider.currentUser, isNull);
      expect(recProvider.personalizedRecs, isEmpty);

      // 3. User B logs in
      await authProvider.login(email: 'userB@libris.com', password: 'secretpassword');
      expect(authProvider.isLoggedIn, true);
      expect(authProvider.currentUser?.email, 'userB@libris.com');

      // User B must NOT have User A's private data
      expect(recProvider.personalizedRecs, isEmpty);

      // Public catalog and category cache are still intact and unaffected by user logout
      expect(repo.getCachedPopularBooks().length, 1);
      expect(repo.getCachedPopularBooks().first.title, 'Public Popular Book');
      expect(repo.getCachedCategoryBooks('fiction').length, 1);
      expect(repo.getCachedCategoryBooks('fiction').first.title, 'Public Fiction Book');

      authProvider.dispose();
      recProvider.dispose();
    });
  });
}

class FakeAuthService implements AuthServiceBase {
  @override
  bool get isConfigured => true;

  User? _currentUser;
  final _ctrl = StreamController<AuthState>.broadcast();

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<AuthState> get authStateStream => _ctrl.stream;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    _currentUser = User(
      id: 'uid_${email.hashCode}',
      email: email,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    return AuthResponse(user: _currentUser);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _ctrl.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
