import 'book.dart';

class LearningPathItem {
  const LearningPathItem({
    required this.bookId,
    required this.orderIndex,
    this.addedAt,
    this.book,
    this.readingStatus,
    this.notesCount = 0,
    this.hasDueReview = false,
  });

  final String bookId;
  final int orderIndex;
  final DateTime? addedAt;
  final Book? book;
  final String? readingStatus; // 'want_to_read', 'reading', 'finished', or null
  final int notesCount;
  final bool hasDueReview;

  factory LearningPathItem.fromJson(Map<String, dynamic> json) {
    Book? parsedBook;
    if (json['book'] is Map<String, dynamic>) {
      final b = json['book'] as Map<String, dynamic>;
      parsedBook = Book(
        isbn13: b['isbn13']?.toString() ?? json['book_id']?.toString() ?? '',
        title: b['title']?.toString() ?? '',
        authors: b['authors']?.toString() ?? '',
        categories: b['categories']?.toString() ?? '',
        description: b['description']?.toString() ?? '',
        thumbnail: b['thumbnail']?.toString() ?? '',
        averageRating: (b['average_rating'] as num?)?.toDouble() ?? 0.0,
        ratingsCount: (b['ratings_count'] as num?)?.toInt() ?? 0,
        publishedDate: b['published_date']?.toString() ?? '',
        pageCount: (b['page_count'] as num?)?.toInt() ?? 0,
        recommendationReason: b['recommendation_reason']?.toString(),
      );
    }

    DateTime? parsedDate;
    if (json['added_at'] is String && (json['added_at'] as String).isNotEmpty) {
      try {
        parsedDate = DateTime.parse(json['added_at']);
      } catch (_) {}
    }

    return LearningPathItem(
      bookId: json['book_id']?.toString() ?? json['bookId']?.toString() ?? '',
      orderIndex: (json['order_index'] as num?)?.toInt() ?? (json['orderIndex'] as num?)?.toInt() ?? 0,
      addedAt: parsedDate,
      book: parsedBook,
      readingStatus: json['reading_status']?.toString() ?? json['readingStatus']?.toString(),
      notesCount: (json['notes_count'] as num?)?.toInt() ?? (json['notesCount'] as num?)?.toInt() ?? 0,
      hasDueReview: json['has_due_review'] == true || json['hasDueReview'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'book_id': bookId,
      'order_index': orderIndex,
      if (addedAt != null) 'added_at': addedAt!.toIso8601String(),
      if (readingStatus != null) 'reading_status': readingStatus,
      'notes_count': notesCount,
      'has_due_review': hasDueReview,
    };
  }

  LearningPathItem copyWith({
    String? bookId,
    int? orderIndex,
    DateTime? addedAt,
    Book? book,
    String? readingStatus,
    int? notesCount,
    bool? hasDueReview,
  }) {
    return LearningPathItem(
      bookId: bookId ?? this.bookId,
      orderIndex: orderIndex ?? this.orderIndex,
      addedAt: addedAt ?? this.addedAt,
      book: book ?? this.book,
      readingStatus: readingStatus ?? this.readingStatus,
      notesCount: notesCount ?? this.notesCount,
      hasDueReview: hasDueReview ?? this.hasDueReview,
    );
  }
}

class LearningPath {
  const LearningPath({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.category,
    this.status = 'active',
    this.books = const [],
    required this.createdAt,
    required this.updatedAt,
    this.totalBooks = 0,
    this.completedBooks = 0,
    this.readingBooks = 0,
    this.notStartedBooks = 0,
    this.progressPercent = 0,
    this.totalNotesCount = 0,
    this.totalReviewsDue = 0,
    this.nextBookId,
  });

  final String id;
  final String userId;
  final String title;
  final String? description;
  final String? category;
  final String status; // 'active', 'completed', 'archived'
  final List<LearningPathItem> books;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Progress intelligence metrics
  final int totalBooks;
  final int completedBooks;
  final int readingBooks;
  final int notStartedBooks;
  final int progressPercent;
  final int totalNotesCount;
  final int totalReviewsDue;
  final String? nextBookId;

  factory LearningPath.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic d) {
      if (d is String && d.isNotEmpty) {
        try {
          return DateTime.parse(d);
        } catch (_) {}
      }
      return DateTime.now();
    }

    final rawBooks = json['books'] is List ? json['books'] as List : [];
    final parsedBooks = rawBooks
        .whereType<Map<String, dynamic>>()
        .map((b) => LearningPathItem.fromJson(b))
        .toList();

    final total = (json['total_books'] as num?)?.toInt() ??
        (json['totalBooks'] as num?)?.toInt() ??
        parsedBooks.length;
    final completed = (json['completed_books'] as num?)?.toInt() ??
        (json['completedBooks'] as num?)?.toInt() ??
        parsedBooks.where((b) => b.readingStatus == 'finished').length;
    final reading = (json['reading_books'] as num?)?.toInt() ??
        (json['readingBooks'] as num?)?.toInt() ??
        parsedBooks.where((b) => b.readingStatus == 'reading').length;
    final notStarted = (json['not_started_books'] as num?)?.toInt() ??
        (json['notStartedBooks'] as num?)?.toInt() ??
        (total - completed - reading).clamp(0, total);
    final percent = (json['progress_percent'] as num?)?.toInt() ??
        (json['progressPercent'] as num?)?.toInt() ??
        (total > 0 ? ((completed / total) * 100).round() : 0);

    return LearningPath(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      status: json['status']?.toString() ?? 'active',
      books: parsedBooks,
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
      totalBooks: total,
      completedBooks: completed,
      readingBooks: reading,
      notStartedBooks: notStarted,
      progressPercent: percent,
      totalNotesCount: (json['total_notes_count'] as num?)?.toInt() ??
          (json['totalNotesCount'] as num?)?.toInt() ??
          0,
      totalReviewsDue: (json['total_reviews_due'] as num?)?.toInt() ??
          (json['totalReviewsDue'] as num?)?.toInt() ??
          0,
      nextBookId: json['next_book_id']?.toString() ?? json['nextBookId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      'status': status,
      'books': books.map((b) => b.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'total_books': totalBooks,
      'completed_books': completedBooks,
      'reading_books': readingBooks,
      'not_started_books': notStartedBooks,
      'progress_percent': progressPercent,
      'total_notes_count': totalNotesCount,
      'total_reviews_due': totalReviewsDue,
      if (nextBookId != null) 'next_book_id': nextBookId,
    };
  }

  LearningPath copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? category,
    String? status,
    List<LearningPathItem>? books,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalBooks,
    int? completedBooks,
    int? readingBooks,
    int? notStartedBooks,
    int? progressPercent,
    int? totalNotesCount,
    int? totalReviewsDue,
    String? nextBookId,
  }) {
    return LearningPath(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      status: status ?? this.status,
      books: books ?? this.books,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalBooks: totalBooks ?? this.totalBooks,
      completedBooks: completedBooks ?? this.completedBooks,
      readingBooks: readingBooks ?? this.readingBooks,
      notStartedBooks: notStartedBooks ?? this.notStartedBooks,
      progressPercent: progressPercent ?? this.progressPercent,
      totalNotesCount: totalNotesCount ?? this.totalNotesCount,
      totalReviewsDue: totalReviewsDue ?? this.totalReviewsDue,
      nextBookId: nextBookId ?? this.nextBookId,
    );
  }
}

