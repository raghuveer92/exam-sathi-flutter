import 'package:dio/dio.dart';

/// User-facing message from API / network failures.
String apiErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is DioException) {
    final message = error.message;
    if (message != null && message.isNotEmpty) {
      return _stripErrorCodePrefix(message);
    }
  }
  if (error is StateError && error.message.isNotEmpty) {
    return error.message;
  }
  final text = error.toString();
  if (text.contains('Exception: ')) {
    return _stripErrorCodePrefix(text.split('Exception: ').last.trim());
  }
  return fallback;
}

String _stripErrorCodePrefix(String message) {
  final colon = message.indexOf(':');
  if (colon > 0 && message.substring(0, colon).contains('_')) {
    return message.substring(colon + 1).trim();
  }
  return message;
}

String _rawApiErrorText(Object error) {
  if (error is DioException) {
    return (error.message ?? '').toUpperCase();
  }
  if (error is StateError) {
    return error.message.toUpperCase();
  }
  return error.toString().toUpperCase();
}

/// Topic mock test has no sheet questions yet (or not enough configured).
bool isMockTestComingSoonError(Object error) {
  final raw = _rawApiErrorText(error);
  return raw.contains('TOPIC_EMPTY') ||
      raw.contains('SHEET_EMPTY') ||
      raw.contains('INSUFFICIENT_QUESTIONS') ||
      raw.contains('SHEET_NOT_CONFIGURED') ||
      raw.contains('NOT ENOUGH QUESTIONS');
}

/// Friendly copy for missing / incomplete topic question banks.
String mockTestUserMessage(
  Object error, {
  String fallback = 'Unable to start the test. Please try again.',
}) {
  if (isMockTestComingSoonError(error)) {
    final raw = _rawApiErrorText(error);
    if (raw.contains('SHEET_NOT_CONFIGURED')) {
      return 'Topic tests for this exam are being set up. Coming soon!';
    }
    if (raw.contains('INSUFFICIENT_QUESTIONS') ||
        raw.contains('NOT ENOUGH QUESTIONS')) {
      return 'More practice questions are on the way for this topic. Check back soon!';
    }
    return 'Practice test for this topic is coming soon. We\'re adding questions — stay tuned!';
  }
  return apiErrorMessage(error, fallback: fallback);
}
