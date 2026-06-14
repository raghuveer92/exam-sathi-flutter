import 'integration_test_reset_stub.dart'
    if (dart.library.html) 'integration_test_reset_web.dart' as impl;

/// Wipes persisted auth/cache so each `app.main()` in integration tests starts clean.
Future<void> resetIntegrationTestPersistence() =>
    impl.resetIntegrationTestPersistence();
