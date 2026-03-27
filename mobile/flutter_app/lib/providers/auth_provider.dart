import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final _svc = SupabaseService.instance;

  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AuthProvider() {
    _user = _svc.currentUser;
    // Listen to auth state changes (e.g. token refresh, sign-out)
    _svc.authStateStream.listen((state) {
      _user = state.session?.user;
      notifyListeners();
    });
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    try {
      final res = await _svc.signIn(email: email, password: password);
      _user = res.user;
      _error = null;
      return _user != null;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'An unexpected error occurred.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> register({required String email, required String password}) async {
    _setLoading(true);
    try {
      final res = await _svc.signUp(email: email, password: password);
      _user = res.user;
      _error = null;
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'An unexpected error occurred.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _svc.signOut();
    _user = null;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }
}
