import '../../domain/entities/book.dart';

class BookDto {
  static Book fromJson(Map<String, dynamic> json) {
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
      similarityScore: (json['similarity_score'] as num?)?.toDouble() ?? (json['final_score'] as num?)?.toDouble(),
      explanation: json['explanation']?.toString(),
      explanationSourceBook: json['explanation_source_book']?.toString(),
      rawSimilarityScore: (json['raw_similarity_score'] as num?)?.toDouble(),
      finalScore: (json['final_score'] as num?)?.toDouble(),
      diversityPenalty: (json['diversity_penalty'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic> toJson(Book book) => {
        'isbn13': book.isbn13,
        'title': book.title,
        'authors': book.authors,
        'categories': book.categories,
        'description': book.description,
        'thumbnail': book.thumbnail,
        'average_rating': book.averageRating,
        'ratings_count': book.ratingsCount,
        'published_date': book.publishedDate,
        'page_count': book.pageCount,
        if (book.similarityScore != null) 'similarity_score': book.similarityScore,
        if (book.explanation != null) 'explanation': book.explanation,
        if (book.explanationSourceBook != null) 'explanation_source_book': book.explanationSourceBook,
        if (book.rawSimilarityScore != null) 'raw_similarity_score': book.rawSimilarityScore,
        if (book.finalScore != null) 'final_score': book.finalScore,
        if (book.diversityPenalty != null) 'diversity_penalty': book.diversityPenalty,
      };
}

class FavoriteBookDto {
  static FavoriteBook fromJson(Map<String, dynamic> json) {
    return FavoriteBook(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      isbn13: json['book_id']?.toString() ?? '',
      bookTitle: json['book_title']?.toString() ?? '',
      thumbnail: json['book_image_url']?.toString() ?? '',
      addedAt: json['added_at'] != null
          ? DateTime.tryParse(json['added_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
