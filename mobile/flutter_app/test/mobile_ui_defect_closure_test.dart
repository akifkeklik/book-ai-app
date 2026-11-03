import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/screens/detail_screen.dart';
import 'package:book_ai_app/screens/recommendation_screen.dart';
import 'package:book_ai_app/screens/categories_screen.dart';
import 'package:book_ai_app/screens/settings_screen.dart';
import 'package:book_ai_app/providers/auth_provider.dart' as app_auth;
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/providers/theme_provider.dart';
import 'package:book_ai_app/providers/catalog_provider.dart';
import 'package:book_ai_app/application/use_cases/view_book_details_use_case.dart';
import 'package:book_ai_app/application/use_cases/manage_recommendations_use_case.dart';
import 'package:book_ai_app/application/use_cases/manage_catalog_use_case.dart';
import 'package:book_ai_app/services/supabase_service.dart';

import 'auth_provider_test.dart' show FakeAuthService;

class FakeBookRepository implements BookRepository {
  final Book sample;
  FakeBookRepository(this.sample);

  @override
  Future<Book?> getBookByIsbn(String isbn) async => sample;

  @override
  Future<List<Book>> getRecommendations(String title) async => [sample];

  @override
  Future<String?> getUserInteraction(String userId, String bookId) async => null;

  @override
  Future<bool> trackActivity({
    required String userId,
    required String activityType,
    required String bookId,
    String? bookName,
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupabaseService implements SupabaseService {
  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeManageCatalogUseCase implements ManageCatalogUseCase {
  @override
  List<Book> getCachedPopularBooks() => <Book>[];

  @override
  Future<List<Book>> getPopularBooks({bool forceRefresh = false, int limit = 20}) async => [];

  @override
  Future<List<Map<String, dynamic>>> getCategories() async => [];

  @override
  Future<int> getTotalBookCount() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theHollowBook = Book(
    isbn13: '9780007121021',
    title: 'The Hollow',
    authors: 'Agatha Christie',
    categories: 'Mystery, Detective, Fiction',
    thumbnail: '',
    description: 'A weekend in the country turns deadly when a prominent doctor is found shot by the swimming pool.',
    publishedDate: '2002',
    averageRating: 3.8,
    ratingsCount: 13000,
    pageCount: 384,
  );

  final trDictionary = {
    'add_to_library': 'Kitaplığıma Ekle',
    'view_my_library': 'Kitaplığımı Görüntüle',
    'manage_shelf': 'Kitaplığımı Düzenle',
    'add_to_favorites': 'Favorilerime Ekle',
    'remove_from_favorites': 'Favorilerimden Kaldır',
    'add_to_reading_list': 'Okuma Listeme Ekle',
    'manage_library': 'Kitaplığıma Ekle',
    'unfavorite': 'Favorilerden Çıkar',
    'want_to_read': 'Okumak İstiyorum',
    'reading': 'Okuyorum',
    'finished': 'Okudum',
    'like': 'Beğen',
    'dislike': 'Beğenme',
    'ai_insight': 'AI ANALİZİ',
    'reading_status': 'Okuma Durumu',
    'ratings': 'değerlendirme',
    'page_count': 'Sayfa Sayısı',
    'year': 'Yıl',
    'about': 'Hakkında',
    'show_less': 'Daha az',
    'read_more': 'Devamını oku',
    'similar_to': "{count} adet '{title}' benzeri kitap",
    'similar_books': 'Benzer Kitaplar',
    'categories': 'Kategoriler',
    'settings': 'Ayarlar',
    'settings_line_spacing': 'Satır Aralığı',
    'line_spacing_normal': 'Normal',
    'line_spacing_relaxed': 'Geniş',
    'language': 'Dil ve Bölge',
  };

  Widget buildDetailApp({
    required Book book,
    required String langCode,
    Map<String, String>? customTranslations,
    double textScale = 1.0,
    Size viewport = const Size(360, 800),
  }) {
    final lang = LanguageProvider();
    lang.setTranslationsForTest(langCode, customTranslations ?? trDictionary);

    final fakeRepo = FakeBookRepository(book);
    final fakeAuth = FakeAuthService();
    final fakeSupabase = FakeSupabaseService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LanguageProvider>.value(value: lang),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider(fakeAuth)),
        ChangeNotifierProvider(create: (_) => FavoritesProvider(fakeSupabase)),
        ChangeNotifierProvider(create: (_) => RecommendationProvider(
          manageRecommendations: ManageRecommendationsUseCase(fakeRepo),
        )),
        Provider<ViewBookDetailsUseCase>(create: (_) => ViewBookDetailsUseCase(fakeRepo)),
        Provider<ManageRecommendationsUseCase>(create: (_) => ManageRecommendationsUseCase(fakeRepo)),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            size: viewport,
          ),
          child: DetailScreen(isbn: book.isbn13, initialBook: book),
        ),
      ),
    );
  }

  group('Defect 1: Zero Raw Translation Keys on The Hollow Book Detail Screen', () {
    testWidgets('Detail screen primary action renders "Kitaplığıma Ekle" and NEVER "manage_library"', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildDetailApp(book: theHollowBook, langCode: 'tr'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Verify "manage_library" does NOT appear anywhere
      expect(find.text('manage_library'), findsNothing, reason: 'Technical key manage_library must NEVER be visible');

      // 2. Verify Turkish human localized action label appears
      expect(find.text('Kitaplığıma Ekle'), findsOneWidget, reason: 'Action label must be Kitaplığıma Ekle');

      // 3. Verify no snake_case strings are displayed in any Text widget
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      for (final textWidget in textWidgets) {
        final content = textWidget.data ?? textWidget.textSpan?.toPlainText() ?? '';
        final isSnakeCaseKey = RegExp(r'^[a-z]+(_[a-z0-9]+)+$').hasMatch(content.trim());
        expect(
          isSnakeCaseKey,
          isFalse,
          reason: 'Rendered text "$content" matches a raw snake_case technical key!',
        );
      }
    });

    testWidgets('Detail screen primary action in English renders "Add to My Library"', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final enDict = {
        'add_to_library': 'Add to My Library',
        'view_my_library': 'View My Library',
        'add_to_favorites': 'Add to Favorites',
        'unfavorite': 'Remove from Favorites',
      };

      await tester.pumpWidget(buildDetailApp(book: theHollowBook, langCode: 'en', customTranslations: enDict));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Add to My Library'), findsOneWidget);
      expect(find.text('manage_library'), findsNothing);
    });

    testWidgets('Detail screen primary action in German renders "Zur Bibliothek hinzufügen"', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final deDict = {
        'add_to_library': 'Zur Bibliothek hinzufügen',
        'view_my_library': 'Meine Bibliothek öffnen',
        'add_to_favorites': 'Zu Favoriten hinzufügen',
        'unfavorite': 'Aus Favoriten entfernen',
      };

      await tester.pumpWidget(buildDetailApp(book: theHollowBook, langCode: 'de', customTranslations: deDict));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Zur Bibliothek hinzufügen'), findsOneWidget);
      expect(find.text('manage_library'), findsNothing);
    });
  });

  group('Defect 2: Real Mobile Overflow Audit & Zero Overflows', () {
    testWidgets('Detail screen bottom bar renders without overflow under 1.5x accessibility scale on 320px phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildDetailApp(
          book: theHollowBook,
          langCode: 'de',
          customTranslations: {
            'add_to_library': 'Zur Bibliothek hinzufügen',
            'add_to_favorites': 'Zu Favoriten hinzufügen',
            'unfavorite': 'Aus Favoriten entfernen',
          },
          textScale: 1.5,
          viewport: const Size(320, 640),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull, reason: 'Zero RenderFlex overflow under 1.5x scale on narrow device');
    });

    testWidgets('Recommendation screen info bar renders long titles without overflow under 1.5x text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final lang = LanguageProvider();
      lang.setTranslationsForTest('tr', trDictionary);

      final widget = ChangeNotifierProvider<LanguageProvider>.value(
        value: lang,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.5),
              size: Size(320, 640),
            ),
            child: RecommendationScreen(
              bookTitle: 'The Complete Works of Agatha Christie: The Hollow Immensely Long Title Mystery Edition',
            ),
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull, reason: 'RecommendationScreen must not overflow on long titles');
    });

    testWidgets('Categories screen grid renders without overflow under 1.5x accessibility text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final lang = LanguageProvider();
      lang.setTranslationsForTest('tr', trDictionary);
      final catalog = CatalogProvider(manageCatalog: FakeManageCatalogUseCase());

      final widget = MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageProvider>.value(value: lang),
          ChangeNotifierProvider<CatalogProvider>.value(value: catalog),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.5),
              size: Size(320, 640),
            ),
            child: CategoriesScreen(),
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull, reason: 'CategoriesScreen grid must not overflow under 1.5x text scale');
    });

    testWidgets('Settings screen language and line spacing rows render without overflow under 1.5x scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final lang = LanguageProvider();
      lang.setTranslationsForTest('tr', trDictionary);
      final themeProvider = ThemeProvider();
      final fakeAuth = FakeAuthService();

      final widget = MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageProvider>.value(value: lang),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider(create: (_) => app_auth.AuthProvider(fakeAuth)),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.5),
              size: Size(320, 640),
            ),
            child: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'SettingsScreen rows must not overflow under 1.5x text scale on narrow width');
    });
  });
}
