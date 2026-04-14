import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final _svc = SupabaseService.instance;

  User? _user;
  bool _isLoading = true;
  String? _error;
  StreamSubscription<AuthState>? _authSubscription;

  User? get currentUser => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AuthProvider() {
    _initAuth();
  }

  /// Bir hata mesajının ağ/bağlantı kaynaklı olup olmadığını kontrol eder.
  bool _isNetworkError(String msg) {
    return msg.contains('Failed to fetch') ||
        msg.contains('ClientException') ||
        msg.contains('SocketException') ||
        msg.contains('XMLHttpRequest error') ||
        msg.contains('Connection refused') ||
        msg.contains('Network is unreachable');
  }

  /// Ham exception'ı kullanıcı dostu Türkçe mesaja dönüştürür.
  String _friendlyError(dynamic e) {
    final raw = e.toString();
    if (_isNetworkError(raw)) {
      return '⚠️ Sunucuya bağlanılamadı.\n'
          'Supabase projeniz uyku modunda olabilir. '
          'supabase.com → Dashboard → "Restore Project" butonuna basın.';
    }
    // AuthException mesajından ham teknik bilgiyi sil
    if (e is AuthException) {
      final msg = e.message;
      if (_isNetworkError(msg)) {
        return '⚠️ Sunucuya bağlanılamadı.\n'
            'Supabase projeniz uyku modunda olabilir. '
            'supabase.com → Dashboard → "Restore Project" butonuna basın.';
      }
      if (msg.contains('Invalid login credentials')) {
        return 'E-posta veya şifre hatalı. Lütfen tekrar deneyin.';
      }
      if (msg.contains('Email not confirmed')) {
        return 'E-posta adresinizi doğrulayın, ardından giriş yapabilirsiniz.';
      }
      if (msg.contains('User already registered')) {
        return 'Bu e-posta adresi zaten kayıtlı.';
      }
      return msg;
    }
    return 'Beklenmeyen bir hata oluştu. Lütfen daha sonra tekrar deneyin.';
  }

  Future<void> _initAuth() async {
    try {
      // 1. Hafızadaki mevcut kullanıcıyı HEMEN kontrol et
      _user = _svc.currentUser;
      if (_user != null) {
        _isLoading = false;
        notifyListeners();
      }

      // 2. Auth state değişimlerini dinle — hatalar SESsizce yutulur, UI'a yansımaz
      _authSubscription = _svc.authStateStream.listen((state) {
        final newUser = state.session?.user;
        if (_user?.id != newUser?.id || _isLoading) {
          _user = newUser;
          _isLoading = false;
          notifyListeners();
        }
      }, onError: (err) {
        // Session restore veya token refresh hataları kullanıcı aksiyonu değil,
        // bu yüzden _error'a yazmıyoruz. Sadece log'a basıyoruz.
        debugPrint('[AuthStream] Sessiz hata (kullanıcıya gösterilmedi): $err');
        _isLoading = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[AuthInit] Sessiz hata: $e');
      _isLoading = false;
      notifyListeners();
    }

    // 3. Mutlak fallback: sonsuz yükleme ekranı asla olmayacak
    Future.delayed(const Duration(seconds: 4), () {
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    _error = null;
    try {
      final res = await _svc.signIn(email: email, password: password);
      _user = res.user;
      return _user != null;
    } on AuthException catch (e) {
      _error = _friendlyError(e);
      return false;
    } catch (e) {
      _error = _friendlyError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> register({required String email, required String password}) async {
    _setLoading(true);
    _error = null;
    try {
      final res = await _svc.signUp(email: email, password: password);
      _user = res.user;
      return true;
    } on AuthException catch (e) {
      _error = _friendlyError(e);
      return false;
    } catch (e) {
      _error = _friendlyError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    try {
      await _svc.signOut();
    } catch (_) {}
    try {
      await Hive.box('books_cache').clear();
    } catch (_) {}
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

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
