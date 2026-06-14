import '../config/test_config.dart';

/// Dev/test OTP strategy — never calls real email services during automation.
abstract final class OtpHelper {
  static const devOtp = '999999';

  /// Returns the OTP to use for [email] in the current environment.
  static String getOtp(String email) {
    if (TestConfig.isDevOrTest) {
      return devOtp;
    }
    throw StateError(
      'OtpHelper.getOtp is only available in dev/test environments. '
      'Set --dart-define=TEST_ENV=dev',
    );
  }
}
