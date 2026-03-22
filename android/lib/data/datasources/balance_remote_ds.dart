import '../../core/constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/network/api_client.dart';
import '../models/balance_model.dart';

/// Remote data source for balance — calls GET /api/v1/balance.
class BalanceRemoteDataSource {
  final ApiClient _apiClient;

  BalanceRemoteDataSource(this._apiClient);

  /// Fetch current balance for the authenticated client.
  Future<BalanceModel> getBalance() async {
    try {
      final json = await _apiClient.get(AppConstants.balanceEndpoint);
      return BalanceModel.fromJson(json);
    } on AuthException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }
}
