import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase/crashlytics_service.dart';
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
    _initFuture ??= _initOnce();
    return _initFuture!;
  }

  Future<void> _initOnce() async {
    try {
      if (kDebugMode) {
        debugPrint('[GoogleAuthService] initialize platform web=$kIsWeb');
      }
      unawaited(CrashlyticsService.log(
        'GoogleSignIn initialize web=$kIsWeb androidOverride=${GoogleAuthConfig.androidServerClientId.isNotEmpty}',
      ));
      await GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? GoogleAuthConfig.webClientId : null,
        // Android reads default_web_client_id from google-services.json unless
        // a build-time override is explicitly provided.
        serverClientId: kIsWeb || GoogleAuthConfig.androidServerClientId.isEmpty
            ? null
            : GoogleAuthConfig.androidServerClientId,
      );
    } on StateError catch (e) {
      // Hot restart on web: GIS script may already be loaded in the page.
      if (!e.message.contains('Future already completed')) rethrow;
    }

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
      if (kDebugMode) {
        debugPrint('[GoogleAuthService] Android authenticate started');
      }
      unawaited(
          CrashlyticsService.log('GoogleSignIn Android authenticate started'));

      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Google Sign-In did not return after account selection',
          const Duration(seconds: 25),
        ),
      );

      final idToken = account.authentication.idToken;
      if (kDebugMode) {
        debugPrint(
          '[GoogleAuthService] Android authenticate completed idToken=${idToken != null && idToken.isNotEmpty}',
        );
      }
      unawaited(CrashlyticsService.log(
        'GoogleSignIn Android authenticate completed idToken=${idToken != null && idToken.isNotEmpty}',
      ));
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google Sign-In did not return an idToken');
      }
      return idToken;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[GoogleAuthService] Android authenticate failed: $e');
      }
      unawaited(CrashlyticsService.recordError(e, stackTrace));
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await GoogleSignIn.instance.signOut();
  }
}
