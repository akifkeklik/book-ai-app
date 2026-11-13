import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/widgets/book_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanguageProvider Global Localization Safeguard Tests', () {
    late LanguageProvider lang;

    setUp(() {
      lang = LanguageProvider();
    });

    test('Missing key "manage_library" in Turkish produces safe localized label and NEVER raw snake_case', () {
      lang.setTranslationsForTest('tr', {});
      final result = lang.translate('manage_library');
      expect(result, isNot(contains('manage_library')));
      expect(result, isNot(contains('_')));
      expect(result, equals('Kitaplığıma Ekle'));
    });

    test('Missing key "add_to_library" in English produces safe localized label', () {
      lang.setTranslationsForTest('en', {});
      final result = lang.translate('add_to_library');
      expect(result, isNot(contains('add_to_library')));
      expect(result, isNot(contains('_')));
      expect(result, equals('Add to My Library'));
    });

    test('Missing key "add_to_library" in German produces safe localized label', () {
      lang.setTranslationsForTest('de', {});
      final result = lang.translate('add_to_library');
      expect(result, isNot(contains('add_to_library')));
      expect(result, isNot(contains('_')));
      expect(result, equals('Zur Bibliothek hinzufügen'));
    });

    test('Missing key "add_to_favorites" in Turkish produces safe localized label', () {
      lang.setTranslationsForTest('tr', {});
      final result = lang.translate('add_to_favorites');
      expect(result, isNot(contains('add_to_favorites')));
      expect(result, isNot(contains('_')));
      expect(result, equals('Favorilerime Ekle'));
    });

    test('Missing key "update_failed" in Turkish produces safe localized message', () {
      lang.setTranslationsForTest('tr', {});
      final result = lang.translate('update_failed');
      expect(result, isNot(contains('update_failed')));
      expect(result, isNot(contains('_')));
      expect(result, equals('Durum güncellenemedi. Lütfen tekrar deneyin.'));
    });

    test('Unknown snake_case key has underscores stripped and title-cased, NEVER raw snake_case', () {
      lang.setTranslationsForTest('en', {});
      final result = lang.translate('custom_shelf_manager_action');
      expect(result, isNot(contains('_')));
      expect(result, equals('Custom Shelf Manager Action'));
    });

    test('Plural safeguard handles missing keys safely without snake_case', () {
      lang.setTranslationsForTest('tr', {});
      final resultOne = lang.plural('unread_book_count', 1);
      final resultOther = lang.plural('unread_book_count', 5);
      expect(resultOne, isNot(contains('_')));
      expect(resultOther, isNot(contains('_')));
      expect(resultOne, equals('Unread Book Count'));
      expect(resultOther, equals('Unread Book Count'));
    });

    test('Fallback to English when active language misses a key', () {
      lang.setTranslationsForTest(
        'tr',
        {'hello': 'Merhaba'},
        fallback: {'hello': 'Hello', 'shelf_action': 'Organize Books'},
      );
      expect(lang.translate('hello'), equals('Merhaba'));
      expect(lang.translate('shelf_action'), equals('Organize Books'));
    });

    test('Genre localization handles underscores safely and cleans raw strings', () {
      lang.setTranslationsForTest('tr', {'genre_science_fiction': 'Bilim Kurgu'});
      expect(lang.localizeGenre('Science Fiction'), equals('Bilim Kurgu'));
      expect(lang.localizeGenre('non_existing_genre'), isNot(contains('_')));
    });

    test('Supported languages helper', () {
      expect(LanguageProvider.isSupported('tr'), isTrue);
      expect(LanguageProvider.isSupported('en'), isTrue);
      expect(LanguageProvider.isSupported('de'), isTrue);
      expect(LanguageProvider.isSupported('fr'), isTrue);
      expect(LanguageProvider.isSupported('ja'), isFalse);
      expect(LanguageProvider.isSupported('TR'), isTrue);
    });
  });

  group('BookCard Recommendation Reason Localization & Safeguard', () {
    testWidgets('localizes trending and taste reasons correctly in Turkish context', (tester) async {
      final lang = LanguageProvider();
      lang.setTranslationsForTest('tr', {
        'trending_on_libris': 'Libris\'te Çok Popüler',
        'based_on_your_taste': 'Zevkinize göre önerildi',
        'reason_because_you_liked': '\'{title}\' kitabını beğendiğiniz için',
      });

      late String trendingResult;
      late String tasteResult;
      late String likedResult;
      late String rawSnakeResult;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: lang,
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                trendingResult = BookCard.localizeReason(ctx, 'Trending on Libris');
                tasteResult = BookCard.localizeReason(ctx, 'curated based on your taste profile');
                likedResult = BookCard.localizeReason(ctx, "Because you liked 'The Hollow'");
                rawSnakeResult = BookCard.localizeReason(ctx, 'reason_surprise_recommendation');
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(trendingResult, equals('Libris\'te Çok Popüler'));
      expect(tasteResult, equals('Zevkinize göre önerildi'));
      expect(likedResult, equals('\'The Hollow\' kitabını beğendiğiniz için'));
      expect(rawSnakeResult, isNot(contains('reason_surprise_recommendation')));
      expect(rawSnakeResult, isNot(contains('_')));
    });
  });
}
