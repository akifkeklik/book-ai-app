import 'package:supabase_flutter/supabase_flutter.dart';

// Minimal auth boundary extracted from SupabaseService.
// Only what AuthProvider needs -- keeps the interface narrow.
abstract class AuthServiceBase {
  User? get currentUser;
  Stream<AuthState> get authStateStream;
  Future<AuthResponse> signIn({required String email, required String password});
  Future<AuthResponse> signUp({required String email, required String password});
  Future<void> signOut();
}