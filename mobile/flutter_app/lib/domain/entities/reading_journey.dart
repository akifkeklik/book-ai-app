import 'book.dart';

enum ReadingGoalType { weekly, annual, category }

class ReadingGoal {
  final ReadingGoalType type;
  final int target;
  final String? category;

  const ReadingGoal({
    this.type = ReadingGoalType.weekly,
    this.target = 1,
    this.category,
  });

  ReadingGoal copyWith({
    ReadingGoalType? type,
    int? target,
    String? category,
  }) {
    return ReadingGoal(
      type: type ?? this.type,
      target: target ?? this.target,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'target': target,
        if (category != null) 'category': category,
      };

  factory ReadingGoal.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'weekly';
    final type = ReadingGoalType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ReadingGoalType.weekly,
    );
    final target = (json['target'] as num?)?.toInt() ?? 1;
    final category = json['category'] as String?;
    return ReadingGoal(type: type, target: target, category: category);
  }
}

class ReadingJourneyItem {
  final String bookId;
  final String status; // 'want_to_read' | 'reading' | 'finished'
  final bool isFavorite;
  final Book book;
  final DateTime? addedAt;

  const ReadingJourneyItem({
    required this.bookId,
    required this.status,
    this.isFavorite = false,
    required this.book,
    this.addedAt,
  });

  ReadingJourneyItem copyWith({
    String? status,
    bool? isFavorite,
  }) {
    return ReadingJourneyItem(
      bookId: bookId,
      status: status ?? this.status,
      isFavorite: isFavorite ?? this.isFavorite,
      book: book,
      addedAt: addedAt,
    );
  }
}

class ReadingJourneyStats {
  final int safeGoal;
  final int completedCount;
  final int readingCount;
  final int wantToReadCount;
  final int progressPercent;
  final bool isGoalReached;
  final List<ReadingJourneyItem> readingBooks;
  final List<ReadingJourneyItem> wantToReadBooks;
  final List<ReadingJourneyItem> completedBooks;

  const ReadingJourneyStats({
    required this.safeGoal,
    required this.completedCount,
    required this.readingCount,
    required this.wantToReadCount,
    required this.progressPercent,
    required this.isGoalReached,
    required this.readingBooks,
    required this.wantToReadBooks,
    required this.completedBooks,
  });
}

/// Pure calculation function for reading journey metrics.
/// Ensures data accuracy:
/// - Completed count strictly requires status == 'finished'
/// - Favorites never inflate reading progress
/// - Bounded percentage calculation without division by zero
ReadingJourneyStats calculateReadingJourney({
  required List<ReadingJourneyItem> items,
  required ReadingGoal goal,
}) {
  final defaultTarget = goal.type == ReadingGoalType.weekly
      ? 1
      : (goal.type == ReadingGoalType.category ? 5 : 20);
  final safeGoal =
      goal.target <= 0 ? defaultTarget : goal.target.clamp(1, 500);

  final allFinished = items.where((i) => i.status == 'finished').toList();
  final readingBooks = items.where((i) => i.status == 'reading').toList();
  final wantToReadBooks =
      items.where((i) => i.status == 'want_to_read').toList();

  final targetCategory = (goal.type == ReadingGoalType.category &&
          goal.category != null &&
          goal.category!.trim().isNotEmpty)
      ? goal.category!.trim().toLowerCase()
      : null;

  final matchingFinished = targetCategory != null
      ? allFinished
          .where((i) => i.book.categories.toLowerCase().contains(targetCategory))
          .toList()
      : allFinished;

  final completedCount = matchingFinished.length;
  final progressPercent =
      ((completedCount / safeGoal) * 100).round().clamp(0, 100);
  final isGoalReached = completedCount >= safeGoal;

  return ReadingJourneyStats(
    safeGoal: safeGoal,
    completedCount: completedCount,
    readingCount: readingBooks.length,
    wantToReadCount: wantToReadBooks.length,
    progressPercent: progressPercent,
    isGoalReached: isGoalReached,
    readingBooks: readingBooks,
    wantToReadBooks: wantToReadBooks,
    completedBooks: allFinished,
  );
}

/// Determines the next recommended book from the personalized recommendations.
/// - Filters out books that are currently being read or already completed.
/// - Prioritizes books already in want_to_read if they appear in recommendations.
/// - Otherwise picks the top recommendation with a genuine attribution/reason.
Book? determineNextBook(
  List<Book> recommendations,
  List<ReadingJourneyItem> libraryItems,
) {
  if (recommendations.isEmpty) return null;

  final readingOrFinishedIsbns = libraryItems
      .where((i) => i.status == 'reading' || i.status == 'finished')
      .map((i) => i.bookId)
      .toSet();

  final wantToReadIsbns = libraryItems
      .where((i) => i.status == 'want_to_read')
      .map((i) => i.bookId)
      .toSet();

  // 1. Priority: candidate in want_to_read that appears in recommendations
  for (final book in recommendations) {
    if (wantToReadIsbns.contains(book.isbn13) &&
        !readingOrFinishedIsbns.contains(book.isbn13)) {
      return book;
    }
  }

  // 2. Priority: top recommended book that isn't already active/completed
  for (final book in recommendations) {
    if (!readingOrFinishedIsbns.contains(book.isbn13)) {
      return book;
    }
  }

  return null;
}
