import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

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
        final token = await _storage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        _logger.d('→ ${options.method} ${options.path}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        _logger.d('← ${response.statusCode} ${response.requestOptions.path}');
        handler.next(response);
      },
      onError: (error, handler) async {
        _logger.e('API Error: ${error.message}', error: error);
        final statusCode = error.response?.statusCode;
        if (statusCode == 401 || statusCode == 403) {
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
}
