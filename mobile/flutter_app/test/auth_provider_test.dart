import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:book_ai_app/providers/auth_provider.dart';
import 'package:book_ai_app/services/auth_service_base.dart';

// ---- Fake implementation of AuthServiceBase (no network, no Supabase init) --
class FakeAuthService implements AuthServiceBase {
  bool configured = true;
  User? _currentUser;
  final _ctrl = StreamController<AuthState>.broadcast();
  bool failNextSignIn = false;
  bool throwRateLimit = false;
  bool signUpRequiresConfirmation = false;
  bool signUpAlreadyExists = false;
  Completer<AuthResponse>? inFlightCompleter;

  @override
  bool get isConfigured => configured;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<AuthState> get authStateStream => _ctrl.stream;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    if (inFlightCompleter != null) {
      return inFlightCompleter!.future;
    }
    if (throwRateLimit) {
      throw const AuthException('over_request_rate_limit: Too many requests');
    }
    if (failNextSignIn || email != 'ok@test.com') {
      throw const AuthException('Invalid login credentials');
    }
    _currentUser = _fakeUser('uid-1', email);
    return AuthResponse(
      user: _currentUser,
      session: _fakeSession(_currentUser!),
    );
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    if (throwRateLimit) {
      throw const AuthException('over_request_rate_limit: Too many requests');
    }
    if (signUpAlreadyExists) {
      // Supabase returns user with empty identities when user already exists
      return AuthResponse(
        user: _fakeUserWithIdentities('uid-exists', email, []),
        session: null,
      );
    }
    if (signUpRequiresConfirmation) {
      final user = _fakeUserWithIdentities('uid-unconfirmed', email, [
        const UserIdentity(
          id: 'id-1',
          identityId: 'id-1',
          userId: 'uid-unconfirmed',
          identityData: {},
          provider: 'email',
          createdAt: '',
          lastSignInAt: '',
          updatedAt: '',
        )
      ]);
      return AuthResponse(user: user, session: null);
    }
    _currentUser = _fakeUser('uid-2', email);
    return AuthResponse(
      user: _currentUser,
      session: _fakeSession(_currentUser!),
    );
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _ctrl.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  User _fakeUser(String id, String email) => User(
        id: id,
        email: email,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      );

  User _fakeUserWithIdentities(String id, String email, List<UserIdentity> identities) => User(
        id: id,
        email: email,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
        identities: identities,
      );

  Session _fakeSession(User user) => Session(
        accessToken: 'fake-jwt',
        tokenType: 'bearer',
        user: user,
      );
}

// ---- Tests -------------------------------------------------------------------
void main() {
  group('AuthProvider - unconfigured state', () {
    test('when auth service is not configured -> fails with auth_error_not_configured', () async {
      final fake = FakeAuthService()..configured = false;
      final auth = AuthProvider(fake);

      final okLogin = await auth.login(email: 'ok@test.com', password: 'pass');
      expect(okLogin, false);
      expect(auth.error, 'auth_error_not_configured');

      final okReg = await auth.register(email: 'ok@test.com', password: 'pass');
      expect(okReg, false);
      expect(auth.error, 'auth_error_not_configured');
      auth.dispose();
    });
  });

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
      expect(auth.error, contains('auth_error_invalid_credentials'));
      auth.dispose();
    });

    test('given rate limit response -> auth_error_rate_limited is returned', () async {
      final fake = FakeAuthService()..throwRateLimit = true;
      final auth = AuthProvider(fake);

      final ok = await auth.login(email: 'ok@test.com', password: 'pass');

      expect(ok, false);
      expect(auth.isLoggedIn, false);
      expect(auth.error, 'auth_error_rate_limited');
      auth.dispose();
    });
  });

  group('AuthProvider - registration flows', () {
    test('registration with direct session -> logged in immediately', () async {
      final auth = AuthProvider(FakeAuthService());

      final ok = await auth.register(email: 'new@test.com', password: 'password123');

      expect(ok, true);
      expect(auth.isLoggedIn, true);
      expect(auth.requiresEmailConfirmation, false);
      expect(auth.currentUser?.id, 'uid-2');
      expect(auth.error, isNull);
      auth.dispose();
    });

    test('registration requiring email confirmation -> returns true but not logged in', () async {
      final fake = FakeAuthService()..signUpRequiresConfirmation = true;
      final auth = AuthProvider(fake);

      final ok = await auth.register(email: 'unconfirmed@test.com', password: 'password123');

      expect(ok, true);
      expect(auth.isLoggedIn, false);
      expect(auth.currentUser, isNull);
      expect(auth.requiresEmailConfirmation, true);
      expect(auth.error, isNull);
      auth.dispose();
    });

    test('registration with existing email -> returns false with auth_error_already_registered', () async {
      final fake = FakeAuthService()..signUpAlreadyExists = true;
      final auth = AuthProvider(fake);

      final ok = await auth.register(email: 'existing@test.com', password: 'password123');

      expect(ok, false);
      expect(auth.isLoggedIn, false);
      expect(auth.requiresEmailConfirmation, false);
      expect(auth.error, 'auth_error_already_registered');
      auth.dispose();
    });
  });

  group('AuthProvider - concurrent submission guard', () {
    test('second simultaneous login tap is dropped immediately', () async {
      final fake = FakeAuthService();
      final completer = Completer<AuthResponse>();
      fake.inFlightCompleter = completer;
      final auth = AuthProvider(fake);

      final firstCall = auth.login(email: 'ok@test.com', password: 'pass');
      expect(auth.isAuthenticating, true);

      // Concurrent second tap while first is in-flight
      final secondCall = await auth.login(email: 'ok@test.com', password: 'pass');
      expect(secondCall, false);

      // Resolve first call
      completer.complete(AuthResponse(
        user: fake._fakeUser('uid-1', 'ok@test.com'),
        session: fake._fakeSession(fake._fakeUser('uid-1', 'ok@test.com')),
      ));

      final firstResult = await firstCall;
      expect(firstResult, true);
      expect(auth.isAuthenticating, false);
      auth.dispose();
    });
  });

  group('AuthProvider - logout', () {
    test('after login then logout -> isLoggedIn false, user null, error null, requiresConfirmation false', () async {
      final auth = AuthProvider(FakeAuthService());
      await auth.login(email: 'ok@test.com', password: 'pass');
      expect(auth.isLoggedIn, true);

      await auth.logout();

      expect(auth.isLoggedIn, false);
      expect(auth.currentUser, isNull);
      expect(auth.requiresEmailConfirmation, false);
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