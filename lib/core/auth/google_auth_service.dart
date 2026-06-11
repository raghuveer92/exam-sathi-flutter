import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_auth_config.dart';

/// Wraps Google Sign-In and returns an idToken for backend verification.
class GoogleAuthService {
  bool _initialized = false;
  Future<void>? _initFuture;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _webAuthSub;

  bool get isAvailable => GoogleAuthConfig.isConfigured;

  /// Call once before renderButton or authenticationEvents (web + mobile).
  Future<void> initialize() => _ensureInitialized();

  Future<void> _ensureInitialized() {
    if (!isAvailable) return Future.value();
    if (_initialized) return Future.value();
    return _initFuture ??= _initOnce();
  }

  Future<void> _initOnce() async {
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? GoogleAuthConfig.webClientId : null,
      // serverClientId is Android/iOS only — web asserts if this is set.
      serverClientId: kIsWeb ? null : GoogleAuthConfig.webClientId,
    );
    _initialized = true;
  }

  /// Mobile/desktop: opens Google sign-in UI and returns an idToken.
  Future<String?> signInAndGetIdToken() async {
    await _ensureInitialized();
    if (kIsWeb) {
      throw UnsupportedError(
        'On web, use the GIS renderButton and listen to authenticationEvents.',
      );
    }

    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );

      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google Sign-In did not return an idToken');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  /// Web: listen while a login/register screen is visible.
  Future<StreamSubscription<GoogleSignInAuthenticationEvent>>
      listenForWebSignIn({
    required void Function(String idToken) onSignedIn,
    void Function(Object error)? onError,
  }) async {
    assert(kIsWeb, 'listenForWebSignIn is web-only');
    await _ensureInitialized();

    await _webAuthSub?.cancel();
    _webAuthSub = GoogleSignIn.instance.authenticationEvents.listen(
      (event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          final idToken = event.user.authentication.idToken;
          if (idToken != null && idToken.isNotEmpty) {
            onSignedIn(idToken);
          } else {
            onError?.call(
              StateError('Google Sign-In did not return an idToken'),
            );
          }
        }
      },
      onError: onError,
    );
    return _webAuthSub!;
  }

  void cancelWebSignInListener() {
    unawaited(_webAuthSub?.cancel());
    _webAuthSub = null;
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await GoogleSignIn.instance.signOut();
  }
}
