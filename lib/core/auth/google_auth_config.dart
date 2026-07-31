/// Google OAuth client IDs for Sign-In.
///
/// Override at build time if needed:
///   --dart-define=GOOGLE_WEB_CLIENT_ID=...
///   --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=...
class GoogleAuthConfig {
  GoogleAuthConfig._();

  /// Web OAuth client used by GIS on Flutter web.
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '1047754395690-mob559u60rvp310udbcegielag53r89k.apps.googleusercontent.com',
  );

  /// Optional Android web client override.
  ///
  /// Leave empty for release/internal-testing builds so google_sign_in_android
  /// reads `default_web_client_id` generated from android/app/google-services.json.
  static const String androidServerClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static bool get isConfigured => webClientId.isNotEmpty;
}
