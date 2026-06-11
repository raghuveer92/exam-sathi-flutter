
import '../models/user_model.dart';
import '../../core/auth/google_auth_service.dart';
import '../../core/local/local_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

class AuthRepository {
  final ApiClient _client;
  final LocalStore _store;
  final GoogleAuthService _googleAuth;

  AuthRepository({
    required ApiClient client,
    required LocalStore store,
    required GoogleAuthService googleAuth,
  })  : _client = client,
        _store = store,
        _googleAuth = googleAuth;

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

  Future<Map<String, dynamic>> signInWithGoogle() async {
    final idToken = await _googleAuth.signInAndGetIdToken();
    if (idToken == null) {
      throw StateError('Google Sign-In was cancelled');
    }
    return signInWithGoogleIdToken(idToken);
  }

  Future<Map<String, dynamic>> signInWithGoogleIdToken(String idToken) async {
    final response = await _client.dio.post(
      ApiEndpoints.googleSignIn,
      data: {'idToken': idToken},
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

  Future<void> cacheUser(UserModel user) async {
    final previousId = _store.getString(LocalStore.cachedUserIdKey);
    final nextId = user.id.toString();
    if (previousId != null && previousId != nextId) {
      await _store.clearUserStudyData();
    }
    await _store.putString(LocalStore.cachedUserIdKey, nextId);
    await _store.putJson(LocalStore.userProfileKey, user.toJson());
  }

  Future<UserModel?> getCachedUser() async {
    final data = _store.getJson(LocalStore.userProfileKey);
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  Future<void> logout() async {
    await _googleAuth.signOut();
    await _client.clearToken();
    await _store.deleteKey(LocalStore.userProfileKey);
    await _store.resetInitialDownloadComplete();
    await _store.clearLastSyncTime();
  }

  /// Permanently deletes the account on the server and wipes all local data.
  Future<void> deleteAccount(String password) async {
    await _client.dio.delete(
      ApiEndpoints.me,
      data: {'password': password},
    );
    await _client.clearToken();
    await _store.clearUserStudyData();
    await _store.deleteKey(LocalStore.cachedUserIdKey);
    await _store.resetInitialDownloadComplete();
    await _store.clearLastSyncTime();
  }

  Future<bool> isLoggedIn() => _client.hasToken();

  /// Offline-first session restore: token + cached profile (or dashboard user).
  Future<UserModel?> restoreSession() async {
    if (!await isLoggedIn()) return null;
    final cached = await getCachedUser();
    if (cached != null) return cached;

    final dashboard = _store.getJson(LocalStore.dashboardKey);
    final user = dashboard?['user'];
    if (user is Map<String, dynamic>) {
      return UserModel.fromJson(user);
    }
    return null;
  }
}
