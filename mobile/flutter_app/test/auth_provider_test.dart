
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:book_ai_app/providers/auth_provider.dart';
import 'package:book_ai_app/services/auth_service_base.dart';

// ---- Fake implementation of AuthServiceBase (no network, no Supabase init) --
class FakeAuthService implements AuthServiceBase {
  User? _currentUser;
  final _ctrl = StreamController<AuthState>.broadcast();
  bool failNextSignIn = false;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<AuthState> get authStateStream => _ctrl.stream;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    if (failNextSignIn || email != 'ok@test.com') {
      throw const AuthException('Invalid login credentials');
    }
    _currentUser = _fakeUser('uid-1', email);
    return AuthResponse(user: _currentUser);
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    _currentUser = _fakeUser('uid-2', email);
    return AuthResponse(user: _currentUser);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _ctrl.add(AuthState(AuthChangeEvent.signedOut, null));
  }

  User _fakeUser(String id, String email) => User(
        id: id,
        email: email,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      );
}

// ---- Tests -------------------------------------------------------------------
void main() {
  group('AuthProvider - login success', () {
    test('given valid credentials -> isLoggedIn true, userId set', () async {
      final auth = AuthProvider(FakeAuthService());

      final ok = await auth.login(email: 'ok@test.com', password: 'pass');

      expect(ok, true);
      expect(auth.isLoggedIn, true);
      expect(auth.currentUser?.id, 'uid-1');
      expect(auth.error, isNull);
      auth.dispose();
    });
  });

  group('AuthProvider - login failure', () {
    test('given wrong credentials -> isLoggedIn false, friendly error shown', () async {
      final auth = AuthProvider(FakeAuthService());

      final ok = await auth.login(email: 'bad@test.com', password: 'bad');

      expect(ok, false);
      expect(auth.isLoggedIn, false);
      expect(auth.error, contains('E-posta veya şifre hatalı'));
      auth.dispose();
    });
  });

  group('AuthProvider - logout', () {
    test('after login then logout -> isLoggedIn false, user null, error null', () async {
      final auth = AuthProvider(FakeAuthService());
      await auth.login(email: 'ok@test.com', password: 'pass');
      expect(auth.isLoggedIn, true);

      await auth.logout();

      expect(auth.isLoggedIn, false);
      expect(auth.currentUser, isNull);
      expect(auth.error, isNull);
      auth.dispose();
    });
  });

  group('AuthProvider - clearError', () {
    test('clearError removes error message', () async {
      final auth = AuthProvider(FakeAuthService());
      await auth.login(email: 'bad@test.com', password: 'bad');
      expect(auth.error, isNotNull);

      auth.clearError();

      expect(auth.error, isNull);
      auth.dispose();
    });
  });

  group('AuthProvider - user isolation', () {
    test('two separate provider instances do not share state', () async {
      final svc1 = FakeAuthService();
      final svc2 = FakeAuthService();
      final auth1 = AuthProvider(svc1);
      final auth2 = AuthProvider(svc2);

      await auth1.login(email: 'ok@test.com', password: 'pass');

      expect(auth1.isLoggedIn, true);
      expect(auth2.isLoggedIn, false);  // svc2 never signed in

      auth1.dispose();
      auth2.dispose();
    });
  });
}