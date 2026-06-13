import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_auth_config.dart';

/// Wraps Google Sign-In and returns an idToken for backend verification.
class GoogleAuthService {
  bool _initialized = false;
  Future<void>? _initFuture;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _webAuthSub;

  final StreamController<String> _webIdTokenController =
      StreamController<String>.broadcast();
  final StreamController<Object> _webErrorController =
      StreamController<Object>.broadcast();

  bool get isAvailable => GoogleAuthConfig.isConfigured;

  /// Fires when GIS returns a credential on web (after user approves sign-in).
  Stream<String> get webIdTokens => _webIdTokenController.stream;

  /// Fires when GIS reports an error on web.
  Stream<Object> get webSignInErrors => _webErrorController.stream;

  /// Call once at app startup (web) and before renderButton or sign-in.
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

    if (kIsWeb) {
      _attachWebCredentialListener();
    }

    _initialized = true;
  }

  /// Subscribe immediately after [GoogleSignIn.initialize] so GIS credentials
  /// are not dropped by the broadcast [authenticationEvents] stream.
  void _attachWebCredentialListener() {
    unawaited(_webAuthSub?.cancel());
    _webAuthSub = GoogleSignIn.instance.authenticationEvents.listen(
      (event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          final idToken = event.user.authentication.idToken;
          if (idToken != null && idToken.isNotEmpty) {
            if (kDebugMode) {
              debugPrint('[GoogleAuthService] Received web idToken');
            }
            _webIdTokenController.add(idToken);
          } else {
            _webErrorController.add(
              StateError('Google Sign-In did not return an idToken'),
            );
          }
        }
      },
      onError: _webErrorController.add,
    );
  }

  /// Mobile/desktop: opens Google sign-in UI and returns an idToken.
  Future<String?> signInAndGetIdToken() async {
    await _ensureInitialized();
    if (kIsWeb) {
      throw UnsupportedError(
        'On web, use the GIS renderButton and listen to webIdTokens.',
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

  Future<void> signOut() async {
    if (!_initialized) return;
    await GoogleSignIn.instance.signOut();
  }
}
