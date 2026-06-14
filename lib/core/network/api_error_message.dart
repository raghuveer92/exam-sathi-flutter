import 'package:dio/dio.dart';

/// User-facing message from API / network failures.
String apiErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is DioException) {
    final message = error.message;
    if (message != null && message.isNotEmpty) return message;
  }
  if (error is StateError && error.message.isNotEmpty) {
    return error.message;
  }
  final text = error.toString();
  if (text.contains('Exception: ')) {
    return text.split('Exception: ').last.trim();
  }
  return fallback;
}
