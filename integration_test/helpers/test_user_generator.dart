/// Generates unique test users for each automation run.
class TestUser {
  const TestUser({
    required this.fullName,
    required this.email,
    required this.password,
  });

  final String fullName;
  final String email;
  final String password;
}

abstract final class TestUserGenerator {
  static const defaultPassword = 'Test@123456';
  static const defaultFullName = 'E2E Test User';

  /// Creates a user with email `test_{timestamp}@examsaathi.test`.
  static TestUser generate({
    String fullName = defaultFullName,
    String password = defaultPassword,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return TestUser(
      fullName: fullName,
      email: 'test_$timestamp@examsaathi.test',
      password: password,
    );
  }
}
