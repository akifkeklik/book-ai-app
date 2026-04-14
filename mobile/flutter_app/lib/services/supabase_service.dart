import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_model.dart';
import '../utils/category_mapper.dart';

class SupabaseService {
  SupabaseService._internal();
  static final SupabaseService instance = SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  // ── Auth ───────────────────────────────────────────────────────────────────

  User? get currentUser => client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateStream => client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return client.auth.signUp(email: email, password: password);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // ── Database ────────────────────────────────────────────────────────────────

  Future<List<Book>> getPopularBooks({int limit = 50}) async {
    try {
      final response = await client
          .from('books')
          .select()
          .order('ratings_count', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));

      return (response as List).map((j) => Book.fromJson(j)).toList();
    } catch (e) {
      throw Exception('Ağ bağlantısı zaman aşımına uğradı veya koptu. Lütfen tekrar deneyin.');
    }
  }

  Future<List<Book>> searchBooks(String query) async {
    try {
      final response = await client
          .from('books')
          .select()
          .or('title.ilike.%$query%,authors.ilike.%$query%,categories.ilike.%$query%')
          .limit(50)
          .timeout(const Duration(seconds: 10));
      return (response as List).map((j) => Book.fromJson(j)).toList();
    } catch (e) {
      throw Exception('Arama sırasında ağ hatası oluştu.');
    }
  }

  Future<List<Book>> getAllBooksByGenre(String category, {int limit = 50, int offset = 0}) async {
    // Senior Logic: Map the UI category to multiple database keywords
    // To handle localized data or naming variations (e.g. History -> History, Biography).
    final keywords = CategoryMapper.getSearchKeywords(category);
    
    if (keywords.isEmpty) return [];

    // Construct the OR filter for ilike on categories
    final orFilter = keywords.map((k) => 'categories.ilike.%$k%').join(',');
    
    try {
      final response = await client
          .from('books')
          .select()
          .or(orFilter)
          .order('ratings_count', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 10));
          
      return (response as List).map((j) => Book.fromJson(j)).toList();
    } catch (e) {
      throw Exception('Kategoriler yüklenirken ağ zaman aşımı oluştu.');
    }
  }

  Future<int> getTotalBookCount() async {
    try {
      // Simplest count that works in most Supabase versions
      final response = await client.from('books').select('id').count(CountOption.exact);
      return (response as dynamic).count ?? 0;
    } catch (_) {
      return 6400; // Fallback to original count
    }
  }

  // ── Favorites ─────────────────────────────────────────────────────────────

  Future<void> addFavorite({
    required String userId,
    required String bookId,
    required String title,
    required String author,
    required String? imageUrl,
  }) async {
    await client.from('favorites').upsert({
      'user_id': userId,
      'book_id': bookId,
      'book_title': title,
      'book_author': author,
      'book_image_url': imageUrl,
      'added_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeFavorite(String userId, String bookId) async {
    await client
        .from('favorites')
        .delete()
        .match({'user_id': userId, 'book_id': bookId});
  }

  Future<List<dynamic>> getFavorites(String userId) async {
    try {
      final response = await client
          .from('favorites')
          .select()
          .eq('user_id', userId)
          .order('added_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return response as List;
    } catch (e) {
      throw Exception('Favoriler alınamadı. Bağlantınızı kontrol edin.');
    }
  }

  // ── Activity & Profile ──────────────────────────────────────────────────

  Future<void> trackActivity({
    required String userId,
    required String activityType,
    required String bookId,
  }) async {
    try {
      await client.from('user_activities').insert({
        'user_id': userId,
        'activity_type': activityType,
        'book_id': bookId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> upsertUserProfile({
    required String userId,
    required List<String> preferredGenres,
    required int readingFrequency,
    required List<String> preferredAuthors,
    required String preferredVibe,
  }) async {
    await client.from('user_profiles').upsert({
      'user_id': userId,
      'preferred_genres': preferredGenres,
      'reading_frequency': readingFrequency,
      'preferred_authors': preferredAuthors,
      'preferred_vibe': preferredVibe,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final response = await client
        .from('user_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return response;
  }

  // ── Book Detail Lookup ─────────────────────────────────────────────────────
  
  Future<Book?> getBookByIsbn(String isbn) async {
    try {
      final response = await client
          .from('books')
          .select()
          .or('isbn13.eq.$isbn,isbn10.eq.$isbn')
          .maybeSingle();
          
      if (response == null) return null;
      return Book.fromJson(response);
    } catch (_) {
      return null;
    }
  }
}
