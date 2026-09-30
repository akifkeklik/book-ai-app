export '../../utils/book_extensions.dart';

class Book {
  final String isbn13;
  final String title;
  final String authors;
  final String categories;
  final String description;
  final String thumbnail;
  final double averageRating;
  final int ratingsCount;
  final String publishedDate;
  final int pageCount;
  final double? similarityScore;
  final String? explanation;
  final String? explanationSourceBook;
  final double? rawSimilarityScore;
  final double? finalScore;
  final double? diversityPenalty;

  const Book({
    required this.isbn13,
    required this.title,
    required this.authors,
    required this.categories,
    required this.description,
    required this.thumbnail,
    required this.averageRating,
    required this.ratingsCount,
    required this.publishedDate,
    required this.pageCount,
    this.similarityScore,
    this.explanation,
    this.explanationSourceBook,
    this.rawSimilarityScore,
    this.finalScore,
    this.diversityPenalty,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Book && other.isbn13 == isbn13);

  @override
  int get hashCode => isbn13.hashCode;

  @override
  String toString() => 'Book(isbn13: $isbn13, title: $title)';
}

class FavoriteBook {
  final String id;
  final String userId;
  final String isbn13;
  final String bookTitle;
  final String thumbnail;
  final DateTime addedAt;

  const FavoriteBook({
    required this.id,
    required this.userId,
    required this.isbn13,
    required this.bookTitle,
    required this.thumbnail,
    required this.addedAt,
  });
}
