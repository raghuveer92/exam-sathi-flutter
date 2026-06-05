
import '../models/user_model.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

class AuthRepository {
  final ApiClient _client;
  final LocalStore _store;

  AuthRepository({
    required ApiClient client,
    required LocalStore store,
  })  : _client = client,
        _store = store;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _client.dio.post(
      ApiEndpoints.login,
      data: {'email': email, 'password': password},
    );
    final body = response.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    await _client.saveToken(data['accessToken'] as String);
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    await cacheUser(user);
    return data;
  }

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    final response = await _client.dio.post(
      ApiEndpoints.register,
      data: {
        'fullName': fullName,
        'email': email,
        'password': password,
        if (phone != null) 'phone': phone,
      },
    );
    final body = response.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    await _client.saveToken(data['accessToken'] as String);
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    await cacheUser(user);
    return data;
  }

  Future<UserModel> getMe() async {
    final response = await _client.dio.get(ApiEndpoints.me);
    final user = UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
    await cacheUser(user);
    return user;
  }

  Future<UserModel?> getCachedUser() async {
    final data = _store.getJson(LocalStore.userProfileKey);
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  Future<void> cacheUser(UserModel user) async {
    await _store.putJson(LocalStore.userProfileKey, user.toJson());
  }

  Future<void> logout() async {
    await _client.clearToken();
    await _store.deleteKey(LocalStore.userProfileKey);
  }

  Future<bool> isLoggedIn() => _client.hasToken();

  /// Offline-first session restore: token + cached profile is enough.
  Future<UserModel?> restoreSession() async {
    if (!await isLoggedIn()) return null;
    return getCachedUser();
  }
}
