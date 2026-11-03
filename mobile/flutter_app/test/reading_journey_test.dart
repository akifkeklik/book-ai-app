import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/entities/reading_journey.dart';

void main() {
  Book mockBook(String id, String title, {String categories = 'Fiction'}) {
    return Book(
      isbn13: id,
      title: title,
      authors: 'Author $id',
      categories: categories,
      description: '',
      thumbnail: '',
      averageRating: 4.5,
      ratingsCount: 10,
      publishedDate: '2024',
      pageCount: 300,
    );
  }

  group('Reading Journey Domain & Calculation Tests', () {
    test('calculateReadingJourney: empty items has 0 progress and safe goal', () {
      final stats = calculateReadingJourney(
        items: [],
        goal: const ReadingGoal(type: ReadingGoalType.annual, target: 20),
      );

      expect(stats.completedCount, equals(0));
      expect(stats.readingCount, equals(0));
      expect(stats.wantToReadCount, equals(0));
      expect(stats.progressPercent, equals(0));
      expect(stats.isGoalReached, isFalse);
      expect(stats.safeGoal, equals(20));
    });

    test('calculateReadingJourney: invalid or zero goal target defaults safely', () {
      final statsZero = calculateReadingJourney(
        items: [],
        goal: const ReadingGoal(type: ReadingGoalType.annual, target: 0),
      );
      expect(statsZero.safeGoal, equals(20));

      final statsWeeklyZero = calculateReadingJourney(
        items: [],
        goal: const ReadingGoal(type: ReadingGoalType.weekly, target: -5),
      );
      expect(statsWeeklyZero.safeGoal, equals(1));
    });

    test('calculateReadingJourney: strictly counts status == finished, ignoring favorites', () {
      final items = [
        ReadingJourneyItem(
          bookId: '1',
          status: 'finished',
          book: mockBook('1', 'Book 1'),
        ),
        ReadingJourneyItem(
          bookId: '2',
          status: 'finished',
          book: mockBook('2', 'Book 2'),
        ),
        ReadingJourneyItem(
          bookId: '3',
          status: 'reading',
          book: mockBook('3', 'Book 3'),
        ),
        ReadingJourneyItem(
          bookId: '4',
          status: 'want_to_read',
          book: mockBook('4', 'Book 4'),
        ),
      ];

      final stats = calculateReadingJourney(
        items: items,
        goal: const ReadingGoal(type: ReadingGoalType.annual, target: 10),
      );

      expect(stats.completedCount, equals(2));
      expect(stats.readingCount, equals(1));
      expect(stats.wantToReadCount, equals(1));
      expect(stats.progressPercent, equals(20)); // 2 / 10 = 20%
      expect(stats.isGoalReached, isFalse);
    });

    test('calculateReadingJourney: progress clamps at 100% when goal reached or exceeded', () {
      final items = [
        ReadingJourneyItem(bookId: '1', status: 'finished', book: mockBook('1', 'Book 1')),
        ReadingJourneyItem(bookId: '2', status: 'finished', book: mockBook('2', 'Book 2')),
        ReadingJourneyItem(bookId: '3', status: 'finished', book: mockBook('3', 'Book 3')),
      ];

      final stats = calculateReadingJourney(
        items: items,
        goal: const ReadingGoal(type: ReadingGoalType.weekly, target: 2),
      );

      expect(stats.completedCount, equals(3));
      expect(stats.progressPercent, equals(100));
      expect(stats.isGoalReached, isTrue);
    });

    test('calculateReadingJourney: topic/category goal strictly filters completed books by category', () {
      final items = [
        ReadingJourneyItem(
          bookId: '1',
          status: 'finished',
          book: mockBook('1', 'Sci-Fi Novel 1', categories: 'Science Fiction, Space'),
        ),
        ReadingJourneyItem(
          bookId: '2',
          status: 'finished',
          book: mockBook('2', 'History Book', categories: 'History, Biography'),
        ),
        ReadingJourneyItem(
          bookId: '3',
          status: 'finished',
          book: mockBook('3', 'Sci-Fi Novel 2', categories: 'Science Fiction, Cyberpunk'),
        ),
      ];

      final stats = calculateReadingJourney(
        items: items,
        goal: const ReadingGoal(
          type: ReadingGoalType.category,
          target: 4,
          category: 'Science Fiction',
        ),
      );

      // Only the 2 Science Fiction books count toward this category target
      expect(stats.completedCount, equals(2));
      expect(stats.safeGoal, equals(4));
      expect(stats.progressPercent, equals(50)); // 2 / 4 = 50%
      expect(stats.isGoalReached, isFalse);
    });

    test('determineNextBook: prioritizes want_to_read books in recommendations', () {
      final rec1 = mockBook('1', 'Rec 1');
      final rec2 = mockBook('2', 'Rec 2');
      final rec3 = mockBook('3', 'Rec 3');

      final items = [
        ReadingJourneyItem(
          bookId: '2',
          status: 'want_to_read',
          book: rec2,
        ),
      ];

      final next = determineNextBook([rec1, rec2, rec3], items);
      expect(next, isNotNull);
      expect(next!.isbn13, equals('2'));
    });

    test('determineNextBook: excludes books already being read or finished', () {
      final rec1 = mockBook('1', 'Rec 1');
      final rec2 = mockBook('2', 'Rec 2');
      final rec3 = mockBook('3', 'Rec 3');

      final items = [
        ReadingJourneyItem(
          bookId: '1',
          status: 'reading',
          book: rec1,
        ),
        ReadingJourneyItem(
          bookId: '2',
          status: 'finished',
          book: rec2,
        ),
      ];

      final next = determineNextBook([rec1, rec2, rec3], items);
      expect(next, isNotNull);
      expect(next!.isbn13, equals('3'));
    });
  });
}
