import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

import '../local/api_call_tracker.dart';
import 'api_endpoints.dart';

/// Dio HTTP client with JWT interceptor.
class ApiClient {
  static const String _tokenKey = 'auth_token';

  final Dio _dio;
  final FlutterSecureStorage _storage;
  final Logger _logger;
  final void Function()? onUnauthorized;

  ApiClient({
    Dio? dio,
    FlutterSecureStorage? storage,
    Logger? logger,
    this.onUnauthorized,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _logger = logger ?? Logger(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiEndpoints.baseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Content-Type': 'application/json'},
            )) {
    _setupInterceptors();
  }

  Dio get dio => _dio;

  void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.extra['_request_start_ms'] =
            DateTime.now().millisecondsSinceEpoch;
        final token = await _storage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        _logger.d('→ ${options.method} ${options.path}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        _logResponseTiming(response.requestOptions, response.statusCode);
        _logger.d('← ${response.statusCode} ${response.requestOptions.path}');
        handler.next(response);
      },
      onError: (error, handler) async {
        _logResponseTiming(
          error.requestOptions,
          error.response?.statusCode,
          failed: true,
          message: error.message,
        );
        _logger.e('API Error: ${error.message}', error: error);
        final statusCode = error.response?.statusCode;
        final path = error.requestOptions.path;
        final isDeleteAccountAttempt =
            error.requestOptions.method == 'DELETE' && path.endsWith('/me');
        if ((statusCode == 401 || statusCode == 403) && !isDeleteAccountAttempt) {
          await _storage.delete(key: _tokenKey);
          onUnauthorized?.call();
        }
        final data = error.response?.data;
        final msg = (data is Map<String, dynamic>) ? data['message'] as String? : null;
        if (msg != null) {
          handler.reject(DioException(
            requestOptions: error.requestOptions,
            response: error.response,
            message: msg,
            type: error.type,
          ));
        } else {
          handler.next(error);
        }
      },
    ));
  }

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<bool> hasToken() async => (await _storage.read(key: _tokenKey)) != null;

  void _logResponseTiming(
    RequestOptions options,
    int? statusCode, {
    bool failed = false,
    String? message,
  }) {
    final started = options.extra['_request_start_ms'] as int?;
    final elapsed = started == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch - started;
    final query = options.queryParameters.isEmpty
        ? ''
        : '?${options.uri.query}';
    final label = '${options.method} ${options.path}$query';

    ApiCallTracker.instance.recordTimed(
      label,
      elapsed,
      statusCode: statusCode,
      detail: failed ? message : null,
    );

    if (failed) {
      _logger.w('[HTTP] ✗ $label → $statusCode (${elapsed}ms) $message');
    } else {
      _logger.i('[HTTP] ✓ $label → $statusCode (${elapsed}ms)');
    }
  }
}
