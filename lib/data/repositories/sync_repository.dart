import '../../core/local/api_call_tracker.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

class SyncRepository {
  final ApiClient _client;

  SyncRepository({required ApiClient client}) : _client = client;

  Future<Map<String, dynamic>> syncCatalog({
    DateTime? since,
    List<int>? examIds,
  }) async {
    ApiCallTracker.instance.record('GET ${ApiEndpoints.syncCatalog}');
    final params = <String, dynamic>{};
    if (since != null) {
      params['since'] = since.toIso8601String();
    }
    if (examIds != null && examIds.isNotEmpty) {
      params['examIds'] = examIds;
    }
    final response = await _client.dio.get(
      ApiEndpoints.syncCatalog,
      queryParameters: params.isEmpty ? null : params,
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncBundle({DateTime? since}) async {
    ApiCallTracker.instance.record('GET ${ApiEndpoints.syncBundle}');
    final response = await _client.dio.get(
      ApiEndpoints.syncBundle,
      queryParameters: since != null ? {'since': since.toIso8601String()} : null,
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> pushChanges(List<Map<String, dynamic>> items) async {
    ApiCallTracker.instance.record('POST ${ApiEndpoints.syncPush}');
    await _client.dio.post(
      ApiEndpoints.syncPush,
      data: {'items': items},
    );
  }
}
