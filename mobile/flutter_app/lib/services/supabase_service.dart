import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/entities/book.dart';
import '../data/models/book_dto.dart';
import '../utils/category_mapper.dart';
import '../config.dart';
import 'auth_service_base.dart';

class SupabaseService implements AuthServiceBase {
  SupabaseService._internal();
  static final SupabaseService instance = SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  // ── Auth ───────────────────────────────────────────────────────────────────

  @override
  bool get isConfigured => AppConfig.isSupabaseConfigured;

  @override
  User? get currentUser => client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  @override
  Stream<AuthState> get authStateStream => client.auth.onAuthStateChange;

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return client.auth.signUp(email: email, password: password);
  }

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  @override
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

      return (response as List).map((j) => BookDto.fromJson(j)).toList();
    } catch (e) {
      throw Exception('Ağ bağlantısı zaman aşımına uğradı veya koptu. Lütfen tekrar deneyin.');
    }
  }

  Future<List<Book>> searchBooks(String query) async {
    try {
      final response = await client
          .from('books')
          .select()
          .or('title.ilike.*$query*,authors.ilike.*$query*,categories.ilike.*$query*')
          .limit(50)
          .timeout(const Duration(seconds: 15));
      return (response as List).map((j) => BookDto.fromJson(j)).toList();
    } catch (e) {
      throw Exception('Arama sırasında ağ hatası oluştu.');
    }
  }

  Future<List<Book>> getAllBooksByGenre(String category, {int limit = 50, int offset = 0}) async {
    // Senior Logic: Map the UI category to multiple database keywords
    final keywords = CategoryMapper.getSearchKeywords(category);
    
    if (keywords.isEmpty) return [];

    // Construct a flat list of conditions for PostgREST .or()
    // We search the 'categories', 'title', and 'description' fields for each keyword.
    // NOTE: We do NOT wrap the entire string in () because the SDK does it for us.
    final conditions = <String>[];
    for (var k in keywords) {
      final sanitized = k.replaceAll("'", "''"); // Basic SQL escape
      conditions.add('categories.ilike.*$sanitized*');
      conditions.add('title.ilike.*$sanitized*');
      // Adding description search only for specific cases or limited keywords to avoid performance hits
      if (keywords.length < 5) {
        conditions.add('description.ilike.*$sanitized*');
      }
    }
    
    final orFilter = conditions.join(',');
    
    try {
      debugPrint('Fetching genre: $category with filters: $orFilter');
      final response = await client
          .from('books')
          .select()
          .or(orFilter)
          .order('ratings_count', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 15));
          
      final data = response as List;
      debugPrint('Found ${data.length} books for $category');
      
      // If we found nothing with ilike, try a broader search or fallback
      if (data.isEmpty && offset == 0) {
        debugPrint('Broadening search for $category...');
        final broaderResponse = await client
            .from('books')
            .select()
            .textSearch('title', category, config: 'english')
            .limit(limit)
            .timeout(const Duration(seconds: 10));
        return (broaderResponse as List).map((j) => BookDto.fromJson(j)).toList();
      }

      return data.map((j) => BookDto.fromJson(j)).toList();
    } catch (e) {
      debugPrint('Supabase Category Error: $e');
      throw Exception('Kategoriler yüklenirken ağ zaman aşımı oluştu.');
    }
  }

  Future<int> getTotalBookCount() async {
    try {
      // Use isbn13 as the primary key for the count optimization
      final response = await client.from('books').select('isbn13').count(CountOption.exact);
      return (response as dynamic).count ?? 6400; // Fallback to baseline
    } catch (e) {
      debugPrint('Error fetching total book count: $e');
      return 6400; // Original hardcoded fallback for robustness
    }
  }

  // ── Favorites ─────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) {
    return client
        .from('favorites')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('added_at', ascending: false);
  }

  Future<void> addFavorite({
    required String userId,
    required String bookId, // This is isbn13
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

  Future<String?> getUserInteraction(String userId, String bookId) async {
    try {
      final response = await client
          .from('user_interactions')
          .select('interaction_type')
          .eq('user_id', userId)
          .eq('book_id', bookId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (response != null && response['interaction_type'] != null) {
        return response['interaction_type'] as String;
      }
    } catch (_) {}
    return null;
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

  bool _isSchemaMismatchError(Object e) {
    final str = e.toString().toLowerCase();
    return str.contains('42703') || // undefined_column
        str.contains('pgrst204') || // column not found in schema cache
        str.contains('could not find the') ||
        (str.contains('column') && str.contains('not exist')) ||
        str.contains('schema cache');
  }

  Future<void> upsertUserProfile({
    required String userId,
    required List<String> preferredGenres,
    required int readingFrequency,
    required List<String> preferredAuthors,
    required String preferredVibe,
  }) async {
    final now = DateTime.now().toIso8601String();
    // Try dual-column upsert first (modern / staging migration schema)
    try {
      await client.from('user_profiles').upsert({
        'id': userId,
        'user_id': userId,
        'preferred_genres': preferredGenres,
        'reading_frequency': readingFrequency,
        'preferred_authors': preferredAuthors,
        'preferred_vibe': preferredVibe,
        'updated_at': now,
      });
      return;
    } catch (e) {
      if (!_isSchemaMismatchError(e)) {
        debugPrint('[SupabaseService] upsertUserProfile failed with non-schema error: $e');
        rethrow;
      }
      debugPrint('[SupabaseService] Detected unmigrated user_profiles schema, falling back to baseline columns: $e');
    }

    // Fallback: unmigrated remote Supabase schema (where user_id or author columns do not exist)
    await client.from('user_profiles').upsert({
      'id': userId,
      'preferred_genres': preferredGenres,
      'reading_frequency': readingFrequency,
      'updated_at': now,
    });
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    // 1. Try querying by user_id (staged migration schema)
    try {
      final response = await client
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (response != null) return response;
    } catch (e) {
      if (!_isSchemaMismatchError(e)) {
        debugPrint('[SupabaseService] Query user_profiles by user_id failed with non-schema error: $e');
        rethrow;
      }
      debugPrint('[SupabaseService] Query user_profiles by user_id column unavailable, trying id: $e');
    }

    // 2. Fallback: unmigrated remote Supabase schema where PK is 'id'
    try {
      final response = await client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('[SupabaseService] Query user_profiles by id failed: $e');
      rethrow;
    }
  }

  // ── Book Detail Lookup ─────────────────────────────────────────────────────
  
  Future<Book?> getBookByIsbn(String isbn) async {
    try {
      // Senior Update: Only query isbn13 as isbn10 does not exist in the schema
      final response = await client
          .from('books')
          .select()
          .eq('isbn13', isbn)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
          
      if (response == null) return null;
      return BookDto.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching book details: $e');
      return null;
    }
  }
}
