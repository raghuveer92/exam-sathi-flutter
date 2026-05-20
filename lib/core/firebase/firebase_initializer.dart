import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'crashlytics_service.dart';

/// Initializes Firebase and platform-specific services.
///
/// Call [initialize] once in main() before runApp().
class FirebaseInitializer {
  const FirebaseInitializer._();

  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Crashlytics only on mobile (not web) — disabled in debug mode
    if (!kIsWeb) {
      await CrashlyticsService.initialize();
    }
  }
}
