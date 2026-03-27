import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_model.dart';

class SupabaseService {
  SupabaseService._internal();
  static final SupabaseService instance = SupabaseService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  // ── Auth ───────────────────────────────────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateStream => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return _client.auth.signUp(email: email, password: password);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  // ── Favorites ──────────────────────────────────────────────────────────────

  Future<List<FavoriteBook>> getFavorites(String userId) async {
    final response = await _client
        .from('favorites')
        .select()
        .eq('user_id', userId)
        .order('added_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => FavoriteBook.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> addFavorite({
    required String userId,
    required String isbn13,
    required String bookTitle,
    required String thumbnail,
  }) async {
    await _client.from('favorites').upsert({
      'user_id': userId,
      'isbn13': isbn13,
      'book_title': bookTitle,
      'thumbnail': thumbnail,
    });
  }

  Future<void> removeFavorite({
    required String userId,
    required String isbn13,
  }) async {
    await _client
        .from('favorites')
        .delete()
        .eq('user_id', userId)
        .eq('isbn13', isbn13);
  }

  Future<bool> isFavorite({
    required String userId,
    required String isbn13,
  }) async {
    final response = await _client
        .from('favorites')
        .select('id')
        .eq('user_id', userId)
        .eq('isbn13', isbn13)
        .maybeSingle();
    return response != null;
  }

  // ── Activity tracking ──────────────────────────────────────────────────────

  Future<void> trackActivity({
    required String userId,
    required String bookName,
    String action = 'view',
  }) async {
    try {
      await _client.from('user_activity').insert({
        'user_id': userId,
        'book_name': bookName,
        'action': action,
      });
    } catch (_) {
      // Non-critical
    }
  }

  Future<List<String>> getRecentlyViewed(String userId, {int limit = 5}) async {
    try {
      final response = await _client
          .from('user_activity')
          .select('book_name')
          .eq('user_id', userId)
          .eq('action', 'view')
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List<dynamic>)
          .map((row) => row['book_name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
