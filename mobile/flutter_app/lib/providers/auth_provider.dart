import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/repositories/book_repository.dart';
import '../services/auth_service_base.dart';
import '../services/sync_coordinator.dart';

class AuthProvider extends ChangeNotifier {
  final AuthServiceBase _svc;
  final BookRepository? _bookRepository;

  User? _user;
  bool _isLoading = true;
  bool _isAuthenticating = false;
  bool _requiresEmailConfirmation = false;
  String? _error;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _fallbackTimer;

  User? get currentUser => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  bool get isAuthenticating => _isAuthenticating;
  bool get requiresEmailConfirmation => _requiresEmailConfirmation;
  String? get error => _error;

  AuthProvider(this._svc, {BookRepository? bookRepository})
      : _bookRepository = bookRepository {
    _initAuth();
  }

  /// Bir hata mesajının ağ/bağlantı kaynaklı olup olmadığını kontrol eder.
  bool _isNetworkError(String msg) {
    return msg.contains('Failed to fetch') ||
        msg.contains('ClientException') ||
        msg.contains('SocketException') ||
        msg.contains('XMLHttpRequest error') ||
        msg.contains('Connection refused') ||
        msg.contains('Network is unreachable') ||
        msg.contains('HandshakeException') ||
        msg.contains('CERTIFICATE_VERIFY_FAILED') ||
        msg.contains('Connection reset') ||
        msg.contains('Connection closed');
  }

  /// Bir hata mesajının parse/format kaynaklı olup olmadığını kontrol eder.
  /// Sunucu JSON yerine HTML döndürdüğünde oluşur.
  bool _isFormatError(String msg) {
    return msg.contains('FormatException') ||
        msg.contains('Unexpected character') ||
        msg.contains('<HTML>') ||
        msg.contains('<html>') ||
        msg.contains('is not a subtype of') ||
        msg.contains('type \'String\' is not');
  }

  /// Ham exception'ı kullanıcı dostu Türkçe mesaja dönüştürür.
  String _friendlyError(dynamic e) {
    final raw = e.toString();

    // Hız sınırlaması (Rate limiting)
    if (raw.toLowerCase().contains('rate limit') ||
        raw.contains('over_request_rate_limit') ||
        raw.contains('Too many requests') ||
        raw.contains('429')) {
      return 'auth_error_rate_limited';
    }

    if (_isFormatError(raw)) return 'auth_error_format';

    // Ağ / bağlantı hataları
    if (_isNetworkError(raw)) return 'auth_error_network';

    // AuthException mesajından ham teknik bilgiyi sil
    if (e is AuthException) {
      final msg = e.message;
      if (msg.toLowerCase().contains('rate limit') ||
          msg.contains('over_request_rate_limit') ||
          msg.contains('Too many requests') ||
          msg.contains('429')) {
        return 'auth_error_rate_limited';
      }
      if (_isFormatError(msg)) return 'auth_error_format';
      if (_isNetworkError(msg)) return 'auth_error_network';
      if (msg.contains('Invalid login credentials')) return 'auth_error_invalid_credentials';
      if (msg.contains('Email not confirmed')) return 'auth_error_unconfirmed';
      if (msg.contains('User already registered') || msg.contains('already registered')) return 'auth_error_already_registered';
      if (msg.contains('email_address_invalid') || msg.contains('invalid_email')) return 'auth_error_invalid_email';
      if (msg.contains('weak_password') || msg.contains('Password should be')) return 'auth_error_weak_password';
      return msg; // Let it fallback to raw if unknown but shouldn't happen often
    }
    return 'auth_error_unexpected';
  }

  Future<void> _initAuth() async {
    try {
      // 1. Hafızadaki mevcut kullanıcıyı HEMEN kontrol et
      _user = _svc.currentUser;
      if (_user != null) {
        _isLoading = false;
        SyncCoordinator.instance.resetAuthFailures(_user!.id);
        notifyListeners();
      }

      // 2. Auth state değişimlerini dinle — hatalar SESSİZCE yutulur, UI'a yansımaz
      _authSubscription = _svc.authStateStream.listen((state) {
        final newUser = state.session?.user;
        if (state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.userUpdated) {
          if (newUser != null) {
            SyncCoordinator.instance.resetAuthFailures(newUser.id);
          }
        }
        if (_user?.id != newUser?.id || _isLoading) {
          final oldUserId = _user?.id;
          _user = newUser;
          _isLoading = false;
          if (oldUserId != null && oldUserId != newUser?.id && _bookRepository != null) {
            _bookRepository.clearUserCache(oldUserId);
          }
          if (newUser != null) {
            SyncCoordinator.instance.resetAuthFailures(newUser.id);
          }
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
    if (_isLoading) {
      _fallbackTimer = Timer(const Duration(seconds: 4), () {
        if (_isLoading) {
          _isLoading = false;
          notifyListeners();
        }
      });
    }
  }

  Future<bool> login({required String email, required String password}) async {
    if (_isAuthenticating) return false;
    if (!_svc.isConfigured) {
      _error = 'auth_error_not_configured';
      notifyListeners();
      return false;
    }
    _isAuthenticating = true;
    _setLoading(true);
    _error = null;
    try {
      final res = await _svc.signIn(email: email, password: password);
      _user = res.user;
      _requiresEmailConfirmation = false;
      if (_user != null) {
        SyncCoordinator.instance.resetAuthFailures(_user!.id);
      }
      return _user != null;
    } on AuthException catch (e) {
      _user = null;
      _error = _friendlyError(e);
      return false;
    } catch (e) {
      _user = null;
      _error = _friendlyError(e);
      return false;
    } finally {
      _isAuthenticating = false;
      _setLoading(false);
    }
  }

  Future<bool> register({required String email, required String password}) async {
    if (_isAuthenticating) return false;
    if (!_svc.isConfigured) {
      _error = 'auth_error_not_configured';
      notifyListeners();
      return false;
    }
    _isAuthenticating = true;
    _setLoading(true);
    _error = null;
    _requiresEmailConfirmation = false;
    try {
      final res = await _svc.signUp(email: email, password: password);
      if (res.session != null) {
        _user = res.user;
        _requiresEmailConfirmation = false;
        return true;
      } else if (res.user != null) {
        if (res.user!.identities != null && res.user!.identities!.isEmpty) {
          _user = null;
          _requiresEmailConfirmation = false;
          _error = 'auth_error_already_registered';
          return false;
        }
        _user = null;
        _requiresEmailConfirmation = true;
        return true;
      }
      return false;
    } on AuthException catch (e) {
      _user = null;
      _requiresEmailConfirmation = false;
      _error = _friendlyError(e);
      return false;
    } catch (e) {
      _user = null;
      _requiresEmailConfirmation = false;
      _error = _friendlyError(e);
      return false;
    } finally {
      _isAuthenticating = false;
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    final currentUserId = _user?.id;
    try {
      await _svc.signOut();
    } catch (_) {}
    if (currentUserId != null && _bookRepository != null) {
      _bookRepository.clearUserCache(currentUserId);
    }
    _user = null;
    _requiresEmailConfirmation = false;
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
    _fallbackTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
