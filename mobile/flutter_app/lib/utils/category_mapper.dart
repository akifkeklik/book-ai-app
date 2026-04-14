class CategoryMapper {
  static const Map<String, List<String>> _genreMap = {
    'Fiction': ['Fiction', 'Juvenile Fiction', 'Novels', 'Classic', 'Roman', 'Kurgu', 'Edebiyat'],
    'Science': ['Science', 'Technology', 'Nature', 'Mathematics', 'Physics', 'Biology', 'Bilim', 'Teknoloji', 'Doğa'],
    'History': ['History', 'Biography & Autobiography', 'Social Science', 'Nonfiction', 'Tarih', 'Biyografi', 'Anı'],
    'Philosophy': ['Philosophy', 'Religion', 'Christian life', 'Spirituality', 'Felsefe', 'Din', 'Maneviyat'],
    'Art': ['Art', 'Design', 'Architecture', 'Photography', 'Sanat', 'Tasarım', 'Mimari'],
    'Mystery': ['Detective and mystery stories', 'Mystery', 'Thriller', 'Crime', 'Gizem', 'Gerilim', 'Polisiye', 'Suç'],
    'Poetry': ['Poetry', 'Drama', 'Plays', 'Şiir', 'Tiyatro', 'Oyun'],
    'Travel': ['Travel', 'Adventure stories', 'Geography', 'Gezi', 'Macera', 'Coğrafya'],
    'Computers': ['Computers', 'Internet', 'Digital', 'Bilgisayar', 'İnternet', 'Teknoloji'],
    'Business': ['Business & Economics', 'Capitalism', 'Finance', 'Management', 'İş', 'Ekonomi', 'Finans', 'Yönetim'],
    'Psychology': ['Psychology', 'Self-Help', 'Mind', 'Psikoloji', 'Kişisel Gelişim', 'Zihin'],
  };

  /// Returns a list of keywords to search for in Supabase for a given genre.
  static List<String> getSearchKeywords(String genre) {
    // 1. Try to find the canonical English name if input is Turkish or localized
    final canonical = _reverseMap[genre] ?? genre;
    
    // 2. Return keywords for the canonical name, or fall back to the input
    return _genreMap[canonical] ?? [genre];
  }

  static Map<String, String>? _cachedReverseMap;
  static Map<String, String> get _reverseMap {
    if (_cachedReverseMap != null) return _cachedReverseMap!;
    
    final map = <String, String>{};
    // Map Turkish labels to English keys
    TurkishToEnglish.forEach((tr, en) => map[tr] = en);
    _cachedReverseMap = map;
    return map;
  }

  static const Map<String, String> TurkishToEnglish = {
    'Kurgu': 'Fiction',
    'Bilim': 'Science',
    'Tarih': 'History',
    'Gizem': 'Mystery',
    'Sanat': 'Art',
    'Felsefe': 'Philosophy',
    'Şiir': 'Poetry',
    'Gezi': 'Travel',
    'Bilgisayar': 'Computers',
    'İş': 'Business',
    'Psikoloji': 'Psychology',
  };

  /// Senior Logic: If the UI category is Turkish but the database is English, we match them here.
  static String? mapTurkishToEnglish(String trGenre) {
    return TurkishToEnglish[trGenre];
  }
}
