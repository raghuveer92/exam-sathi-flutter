/// Runtime configuration for integration / E2E tests.
abstract final class TestConfig {
  /// `dev` | `test` | `prod`
  static const environment =
      String.fromEnvironment('TEST_ENV', defaultValue: 'dev');

  static const integrationTest =
      bool.fromEnvironment('INTEGRATION_TEST', defaultValue: true);

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );

  static bool get isDevOrTest =>
      environment == 'dev' || environment == 'test';

  static Duration get defaultTimeout =>
      isDevOrTest ? const Duration(seconds: 60) : const Duration(seconds: 90);

  static Duration get pumpSettleTimeout =>
      isDevOrTest ? const Duration(seconds: 30) : const Duration(seconds: 45);
}
