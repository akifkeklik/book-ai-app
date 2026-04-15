class CategoryMapper {
  // Map of high-level genres to many potential database keywords
  static const Map<String, List<String>> _genreMap = {
    'Fiction': ['Fiction', 'Juvenile Fiction', 'Novel', 'Literature', 'Kurgu', 'Roman', 'Edebiyat'],
    'Science': ['Science', 'Technology', 'Nature', 'Mathematics', 'Physics', 'Biology', 'Bilim', 'Teknoloji', 'Doğa', 'Matematik', 'Fizik', 'Biyoloji'],
    'History': ['History', 'Biography', 'Autobiography', 'Biography & Autobiography', 'Tarih', 'Biyografi', 'Otobiyografi'],
    'Philosophy': ['Philosophy', 'Religion', 'Psychology', 'Felsefe', 'Din', 'Psikoloji'],
    'Mystery': ['Mystery', 'Thriller', 'Crime', 'Detective', 'Detective and mystery stories', 'Gizem', 'Gerilim', 'Suç', 'Dedektif'],
    'Classic': ['Classic', 'Literary', 'Antique', 'Klasik', 'Antik'],
    'Art': ['Art', 'Design', 'Architecture', 'Photography', 'Sanat', 'Tasarım', 'Mimari'],
    'Travel': ['Travel', 'Adventure stories', 'Geography', 'Gezi', 'Macera', 'Coğrafya'],
    'Business': ['Business & Economics', 'Capitalism', 'Finance', 'Management', 'İş', 'Ekonomi', 'Finans', 'Yönetim'],
    'Fantasy': ['Fantasy', 'Magic', 'Fairy Tales', 'Fantastik', 'Büyü', 'Masal'],
    'Romance': ['Romance', 'Love Stories', 'Romantik', 'Aşk'],
    'Poetry': ['Poetry', 'Şiir'],
    'Self-Help': ['Self-Help', 'Kişisel Gelişim'],
  };

  static const Map<String, String> _trToEn = {
    'Kurgu': 'Fiction',
    'Roman': 'Fiction',
    'Bilim': 'Science',
    'Tarih': 'History',
    'Biyografi': 'History',
    'Felsefe': 'Philosophy',
    'Din': 'Philosophy',
    'Gizem': 'Mystery',
    'Gerilim': 'Mystery',
    'Suç': 'Mystery',
    'Klasik': 'Classic',
    'Sanat': 'Art',
    'Gezi': 'Travel',
    'İş': 'Business',
    'Psikoloji': 'Psychology',
    'Aşk': 'Romance',
    'Romantik': 'Romance',
    'Şiir': 'Poetry',
    'Kişisel Gelişim': 'Self-Help',
    'Fantastik': 'Fantasy',
  };

  /// Returns a list of keywords to search for in Supabase for a given genre.
  static List<String> getSearchKeywords(String genre) {
    if (genre.isEmpty) return [];
    
    final lookup = genre.trim();
    
    // 1. Try exact match in trToEn
    String? canonical = _trToEn[lookup];
    
    // 2. Try case-insensitive matching
    if (canonical == null) {
      final lowerLookup = lookup.toLowerCase();
      
      // Check Turkish keys case-insensitively
      for (var entry in _trToEn.entries) {
        if (entry.key.toLowerCase() == lowerLookup) {
          canonical = entry.value;
          break;
        }
      }
      
      // Check English keys case-insensitively
      if (canonical == null) {
        for (var key in _genreMap.keys) {
          if (key.toLowerCase() == lowerLookup) {
            canonical = key;
            break;
          }
        }
      }
    }

    // Default to the input if no mapping found
    canonical ??= genre;
    
    return _genreMap[canonical] ?? [canonical];
  }

  static String? mapTurkishToEnglish(String trGenre) {
    return _trToEn[trGenre];
  }
}
