import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Configures Firebase Crashlytics to capture Flutter and Dart errors.
///
/// Call [initialize] after Firebase.initializeApp() in FirebaseInitializer.
class CrashlyticsService {
  const CrashlyticsService._();

  static Future<void> initialize() async {
    // Disable collection in debug — only collect in release builds
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    // Forward Flutter framework errors
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Forward uncaught async / isolate errors
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Attach the authenticated user's ID to crash reports.
  static Future<void> setUser({
    required String userId,
    String? email,
  }) async {
    if (kDebugMode) return;
    await FirebaseCrashlytics.instance.setUserIdentifier(userId);
    if (email != null) {
      await FirebaseCrashlytics.instance.setCustomKey('email', email);
    }
  }

  /// Remove the user after logout.
  static Future<void> clearUser() async {
    if (kDebugMode) return;
    await FirebaseCrashlytics.instance.setUserIdentifier('');
  }

  /// Write a breadcrumb message visible in the Crashlytics console.
  static Future<void> log(String message) async {
    if (kDebugMode) return;
    await FirebaseCrashlytics.instance.log(message);
  }

  /// Manually record a non-fatal error.
  static Future<void> recordError(
    Object exception,
    StackTrace? stackTrace, {
    bool fatal = false,
  }) async {
    if (kDebugMode) return;
    await FirebaseCrashlytics.instance.recordError(
      exception,
      stackTrace,
      fatal: fatal,
    );
  }
}
