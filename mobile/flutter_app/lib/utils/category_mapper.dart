class CategoryMapper {
  // Map of canonical genres to potential database and source keywords
  static const Map<String, List<String>> _genreMap = {
    'Fiction': ['Fiction', 'Novel', 'Novels', 'Literature', 'Kurgu', 'Roman', 'Edebiyat'],
    'Young Adult & Children': [
      'Young Adult & Children',
      'Young Adult',
      'Juvenile Fiction',
      'Juvenile Nonfiction',
      "Children's stories",
      'Children',
      'Children\'s',
      'Fairy tales',
      'Gençlik',
      'Çocuk'
    ],
    'Science Fiction': [
      'Science Fiction',
      'Science fiction',
      'Sci-Fi',
      'Space opera',
      'Life on other planets',
      'Bilim Kurgu'
    ],
    'Fantasy': ['Fantasy', 'Fantasy fiction', 'Magic', 'Fairy Tales', 'Fantastik', 'Büyü', 'Masal'],
    'Mystery & Thriller': [
      'Mystery & Thriller',
      'Mystery',
      'Thriller',
      'Crime',
      'Detective',
      'Detective and mystery stories',
      'True crime',
      'Crime fiction',
      'Gizem',
      'Gerilim',
      'Polisiye',
      'Suç'
    ],
    'Horror': ['Horror', 'Horror tales', 'Horror fiction', 'Ghost stories', 'Korku'],
    'Romance': ['Romance', 'Love Stories', 'Man-woman relationships', 'Chick lit', 'Romantik', 'Aşk'],
    'Biography & Memoir': [
      'Biography & Memoir',
      'Biography',
      'Autobiography',
      'Biography & Autobiography',
      'Authors',
      'Memoir',
      'Memoirs',
      'Biyografi',
      'Otobiyografi',
      'Anı'
    ],
    'History': ['History', 'Tarih'],
    'Philosophy': ['Philosophy', 'Felsefe'],
    'Religion & Spirituality': [
      'Religion & Spirituality',
      'Religion',
      'Christian life',
      'Bible',
      'Spirituality',
      'Din',
      'Maneviyat'
    ],
    'Psychology': [
      'Psychology',
      'Body, mind & spirit',
      'Family & relationships',
      'Psikoloji'
    ],
    'Self-Development': ['Self-Development', 'Self-Help', 'Conduct of life', 'Personal finance', 'Kişisel Gelişim'],
    'Business': ['Business', 'Business & Economics', 'Capitalism', 'Finance', 'Management', 'İş', 'Ekonomi', 'Finans', 'Yönetim'],
    'Science': ['Science', 'Technology', 'Nature', 'Mathematics', 'Physics', 'Biology', 'Bilim', 'Doğa', 'Matematik', 'Fizik', 'Biyoloji'],
    'Technology': ['Technology', 'Computers', 'Engineering', 'Technology & engineering', 'Teknoloji', 'Mühendislik'],
    'Comics & Graphic Novels': [
      'Comics & Graphic Novels',
      'Comics',
      'Graphic novels',
      'Graphic novel',
      'Comic books',
      'Çizgi Roman'
    ],
    'Drama & Plays': ['Drama & Plays', 'Drama', 'Plays', 'English drama', 'Performing arts', 'Tiyatro', 'Oyun'],
    'Poetry': ['Poetry', 'Literary collections', 'American poetry', 'Şiir'],
    'Social Sciences': ['Social Sciences', 'Social science', 'Political science', 'Law', 'Sosyal Bilimler', 'Siyaset', 'Hukuk'],
    'Art & Design': ['Art & Design', 'Art', 'Design', 'Architecture', 'Photography', 'Music', 'Sanat', 'Tasarım', 'Mimari'],
    'Food & Cooking': ['Food & Cooking', 'Cooking', 'Cookery', 'Food', 'Yemek', 'Mutfak'],
    'Travel': ['Travel', 'Adventure stories', 'Geography', 'Gezi', 'Macera', 'Coğrafya'],
    'Health & Wellness': ['Health & Wellness', 'Health', 'Fitness', 'Medical', 'Health & fitness', 'Sağlık', 'Tıp'],
    'Humor & Satire': ['Humor & Satire', 'Humor', 'Satire', 'Wit and humor', 'Mizah', 'Hiciv'],
    'Education & Reference': ['Education & Reference', 'Education', 'Reference', 'Study aids', 'Eğitim', 'Referans'],
    'Sports & Games': ['Sports & Games', 'Sports', 'Games', 'Games & activities', 'Sports & recreation', 'Spor', 'Oyunlar'],
    'Crafts & Hobbies': ['Crafts & Hobbies', 'Crafts', 'Hobbies', 'Gardening', 'El Sanatları', 'Hobiler'],
    // Backward-compatibility aliases
    'Classic': ['Classic', 'Literary', 'Antique', 'Klasik', 'Antik'],
    'Mystery': ['Mystery', 'Thriller', 'Crime', 'Detective', 'Detective and mystery stories', 'Gizem', 'Gerilim', 'Suç', 'Dedektif'],
    'Self-Help': ['Self-Help', 'Kişisel Gelişim', 'Self-Development'],
  };

  static const Map<String, String> _trToEn = {
    'Kurgu': 'Fiction',
    'Roman': 'Fiction',
    'Edebiyat': 'Fiction',
    'Gençlik & Çocuk': 'Young Adult & Children',
    'Gençlik': 'Young Adult & Children',
    'Çocuk': 'Young Adult & Children',
    'Bilim Kurgu': 'Science Fiction',
    'Fantastik': 'Fantasy',
    'Gizem & Gerilim': 'Mystery & Thriller',
    'Polisiye': 'Mystery & Thriller',
    'Gizem': 'Mystery & Thriller',
    'Gerilim': 'Mystery & Thriller',
    'Suç': 'Mystery & Thriller',
    'Korku': 'Horror',
    'Romantik': 'Romance',
    'Aşk': 'Romance',
    'Biyografi & Anı': 'Biography & Memoir',
    'Biyografi': 'Biography & Memoir',
    'Otobiyografi': 'Biography & Memoir',
    'Anı': 'Biography & Memoir',
    'Tarih': 'History',
    'Felsefe': 'Philosophy',
    'Din & Maneviyat': 'Religion & Spirituality',
    'Din': 'Religion & Spirituality',
    'Maneviyat': 'Religion & Spirituality',
    'Psikoloji': 'Psychology',
    'Kişisel Gelişim': 'Self-Development',
    'İş & Ekonomi': 'Business',
    'İş': 'Business',
    'Ekonomi': 'Business',
    'Bilim': 'Science',
    'Teknoloji': 'Technology',
    'Çizgi Roman': 'Comics & Graphic Novels',
    'Tiyatro & Oyun': 'Drama & Plays',
    'Tiyatro': 'Drama & Plays',
    'Oyun': 'Drama & Plays',
    'Şiir': 'Poetry',
    'Sosyal Bilimler': 'Social Sciences',
    'Siyaset': 'Social Sciences',
    'Sanat & Tasarım': 'Art & Design',
    'Sanat': 'Art & Design',
    'Tasarım': 'Art & Design',
    'Yemek & Mutfak': 'Food & Cooking',
    'Yemek': 'Food & Cooking',
    'Gezi': 'Travel',
    'Sağlık & Yaşam': 'Health & Wellness',
    'Sağlık': 'Health & Wellness',
    'Mizah & Hiciv': 'Humor & Satire',
    'Mizah': 'Humor & Satire',
    'Eğitim & Referans': 'Education & Reference',
    'Eğitim': 'Education & Reference',
    'Spor & Oyunlar': 'Sports & Games',
    'Spor': 'Sports & Games',
    'El Sanatları & Hobiler': 'Crafts & Hobbies',
    'El Sanatları': 'Crafts & Hobbies',
    'Klasik': 'Classic',
  };

  /// Returns a list of keywords to search for in Supabase for a given genre.
  static List<String> getSearchKeywords(String genre) {
    if (genre.isEmpty) return [];

    final lookup = genre.trim();

    // 1. Try exact match in trToEn
    String? canonical = _trToEn[lookup];

    // 2. Try case-insensitive matching in Turkish dictionary
    if (canonical == null) {
      final lowerLookup = lookup.toLowerCase();

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
