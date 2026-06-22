import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'analytics_service.dart';
import 'crashlytics_service.dart';

/// Initializes Firebase and platform-specific services.
///
/// Call [initialize] once in main() before runApp().
class FirebaseInitializer {
  const FirebaseInitializer._();

  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        Firebase.app();
      }
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }

    // Analytics — enabled on all mobile builds (debug + release)
    await AnalyticsService.initialize();

    // Crashlytics only on mobile (not web) — disabled in debug mode
    if (!kIsWeb) {
      await CrashlyticsService.initialize();
    }
  }
}
