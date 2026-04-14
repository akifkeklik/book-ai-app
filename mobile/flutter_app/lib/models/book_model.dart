import 'dart:convert';

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
  final String? aiNote;

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
    this.aiNote,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      isbn13: json['isbn13']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Title',
      authors: json['authors']?.toString() ?? 'Unknown Author',
      categories: json['categories']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0.0,
      ratingsCount: (json['ratings_count'] as num?)?.toInt() ?? 0,
      publishedDate: json['published_date']?.toString() ?? '',
      pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
      similarityScore: (json['similarity_score'] as num?)?.toDouble(),
      aiNote: json['ai_note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'isbn13': isbn13,
        'title': title,
        'authors': authors,
        'categories': categories,
        'description': description,
        'thumbnail': thumbnail,
        'average_rating': averageRating,
        'ratings_count': ratingsCount,
        'published_date': publishedDate,
        'page_count': pageCount,
        if (similarityScore != null) 'similarity_score': similarityScore,
        if (aiNote != null) 'ai_note': aiNote,
      };

  /// Aliases for database compatibility
  String get author => authors;
  String get genre => primaryCategory;

  /// Formatted authors list for display.
  String get authorsFormatted =>
      authors.replaceAll('|', ', ').replaceAll(';', ', ');

  /// First listed category.
  String get primaryCategory =>
      categories.split(RegExp(r'[|;,]')).first.trim();

  /// All categories as a list.
  List<String> get categoryList =>
      categories.split(RegExp(r'[|;,]')).map((c) => c.trim()).where((c) => c.isNotEmpty).toList();

  /// Cover URL with CORS fix (HTTPS override). Returns empty if none.
  String get coverUrl {
    if (thumbnail.isEmpty) return '';
    // Web strict CORS blocks mixed-content (http on https), Google Books API returns http sometimes.
    return thumbnail.replaceFirst('http://', 'https://');
  }

  /// OpenLibrary fallback based on ISBN
  String get openLibraryCoverUrl {
    if (isbn13.isEmpty) return '';
    // Both ISBN-10 and ISBN-13 can be queried. default=false forces 404 if missing.
    return 'https://covers.openlibrary.org/b/isbn/$isbn13-L.jpg?default=false';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Book && other.isbn13 == isbn13);

  @override
  int get hashCode => isbn13.hashCode;

  @override
  String toString() => 'Book(isbn13: $isbn13, title: $title)';
}

/// Lightweight favourite record stored in Supabase.
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

  factory FavoriteBook.fromJson(Map<String, dynamic> json) {
    return FavoriteBook(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      isbn13: json['isbn13']?.toString() ?? '',
      bookTitle: json['book_title']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      addedAt: json['added_at'] != null
          ? DateTime.tryParse(json['added_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
