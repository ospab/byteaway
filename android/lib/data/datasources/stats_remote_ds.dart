import '../../core/constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/network/api_client.dart';
import '../models/traffic_record_model.dart';

/// Remote data source for traffic statistics.
class StatsRemoteDataSource {
  final ApiClient _apiClient;

  StatsRemoteDataSource(this._apiClient);

  /// Fetch traffic history for the last [days] days.
  Future<List<TrafficRecordModel>> getTrafficHistory({int days = 30}) async {
    try {
      final json = await _apiClient.get(
        AppConstants.statsEndpoint,
        queryParameters: {'days': days},
      );

      final records = json['records'] as List<dynamic>? ?? [];
      return records
          .map((r) => TrafficRecordModel.fromJson(r as Map<String, dynamic>))
          .toList();
    } on AuthException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }
}
