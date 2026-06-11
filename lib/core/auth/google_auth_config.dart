/// Google OAuth client IDs for Sign-In.
///
/// Override at build time if needed:
///   --dart-define=GOOGLE_WEB_CLIENT_ID=...
class GoogleAuthConfig {
  GoogleAuthConfig._();

  /// Web OAuth client — also used as serverClientId on Android for idToken.
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '705998749535-rg78efbe1kr64rppef6fd6vnpu98vvdj.apps.googleusercontent.com',
  );

  /// Android OAuth client (from Firebase / Google Cloud Console).
  static const String androidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue:
        '705998749535-k8bolj448ag0es1rsg0njiqfd128m7ph.apps.googleusercontent.com',
  );

  static bool get isConfigured => webClientId.isNotEmpty;
}
