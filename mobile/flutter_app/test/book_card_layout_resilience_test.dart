import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/widgets/book_card.dart';
import 'package:provider/provider.dart';

class TestLanguageProvider extends LanguageProvider {
  final Map<String, String> strings;
  TestLanguageProvider(this.strings);

  @override
  String translate(String key, {Map<String, String>? args}) {
    String value = strings[key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }
}

Widget _createTestWidget({
  required Widget child,
  double textScale = 1.0,
  Map<String, String> strings = const {},
}) {
  return ChangeNotifierProvider<LanguageProvider>.value(
    value: TestLanguageProvider(strings),
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          size: const Size(400, 800),
        ),
        child: Scaffold(
          body: Center(child: child),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Book makeBook({
    required String isbn,
    required String title,
    required String authors,
    String? reason,
    double? similarity,
  }) {
    return Book(
      isbn13: isbn,
      title: title,
      authors: authors,
      categories: 'Science Fiction, Speculative',
      description: 'A detailed exploration of literary resilience.',
      thumbnail: '',
      averageRating: 4.85,
      ratingsCount: 14200,
      pageCount: 890,
      publishedDate: '2024-05-12',
      recommendationReason: reason,
      similarityScore: similarity,
    );
  }

  final extremeBook = makeBook(
    isbn: '9780123456789',
    title: 'An Unusually Immensely Long Title That Spans Multiple Lines In The Card Header And Needs Careful Ellipsis Without Overflowing Container',
    authors: 'Prof. Alexander Bartholomew Christopher Dumbledore-Enderby III, Dr. Genevieve Penelope Montgomery',
    reason: "Because you liked 'Spider's Web'",
    similarity: 0.94,
  );

  group('BookCard Layout Resilience & Text Scale Robustness', () {
    testWidgets('BookCard renders without overflow under standard 1.0 text scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final widget = _createTestWidget(
        child: SizedBox(
          width: 160,
          height: 320,
          child: BookCard(book: extremeBook, width: null),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull, reason: 'Must not throw any RenderFlex overflow');
      expect(find.byType(BookCard), findsOneWidget);
    });

    testWidgets('BookCard renders without overflow under 1.5x accessibility text scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final widget = _createTestWidget(
        textScale: 1.5,
        child: SizedBox(
          width: 180,
          height: 380,
          child: BookCard(book: extremeBook, width: null),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull, reason: 'Must not throw overflow even at 1.5x font scale');
      expect(find.byType(BookCard), findsOneWidget);
    });

    testWidgets('BookCard renders horizontal list tile layout safely with long metadata', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final widget = _createTestWidget(
        child: SizedBox(
          width: 160,
          child: BookCard(book: extremeBook, width: 160),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });
  });

  group('BookCard Reason Localization Robustness', () {
    final trStrings = {
      'reason_because_you_liked': "'{title}' kitabını beğendiğiniz için",
      'trending_on_libris': "Libris'te Çok Popüler",
      'reason_from_reading_list': "Okuma listenizden: '{title}'",
      'reason_enjoy_genre': '{genre} türünü sevdiğiniz için',
    };

    final deStrings = {
      'reason_from_reading_list': "Aus Ihrer Leseliste: '{title}'",
    };

    testWidgets('localizes "because you liked" in Turkish', (tester) async {
      final book = makeBook(
        isbn: '9780001',
        title: 'Dune Messiah',
        authors: 'Frank Herbert',
        reason: "Because you liked 'Dune'",
      );

      final widget = _createTestWidget(child: BookCard(book: book, width: 200), strings: trStrings);
      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("'Dune' kitabını beğendiğiniz için"), findsOneWidget);
    });

    testWidgets('localizes "trending on libris" in Turkish', (tester) async {
      final book = makeBook(
        isbn: '9780002',
        title: 'Foundation',
        authors: 'Isaac Asimov',
        reason: 'Trending on Libris right now',
      );

      final widget = _createTestWidget(child: BookCard(book: book, width: 200), strings: trStrings);
      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("Libris'te Çok Popüler"), findsOneWidget);
    });

    testWidgets('localizes "from your reading list" in German', (tester) async {
      final book = makeBook(
        isbn: '9780003',
        title: 'Hyperion',
        authors: 'Dan Simmons',
        reason: "From your reading list: 'Ilium'",
      );

      final widget = _createTestWidget(child: BookCard(book: book, width: 200), strings: deStrings);
      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("Aus Ihrer Leseliste: 'Ilium'"), findsOneWidget);
    });

    testWidgets('localizes "because you enjoy Genre" in Turkish', (tester) async {
      final book = makeBook(
        isbn: '9780004',
        title: 'Neuromancer',
        authors: 'William Gibson',
        reason: 'Because you enjoy Cyberpunk',
      );

      final widget = _createTestWidget(child: BookCard(book: book, width: 200), strings: trStrings);
      await tester.pumpWidget(widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("Cyberpunk türünü sevdiğiniz için"), findsOneWidget);
    });
  });
}
