import '../domain/entities/book.dart';

extension BookUIExtensions on Book {
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
    return thumbnail.replaceFirst('http://', 'https://');
  }

  /// OpenLibrary fallback based on ISBN
  String get openLibraryCoverUrl {
    if (isbn13.isEmpty) return '';
    return 'https://covers.openlibrary.org/b/isbn/$isbn13-L.jpg?default=false';
  }
}
