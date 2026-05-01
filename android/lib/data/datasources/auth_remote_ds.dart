import '../../core/constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/network/api_client.dart';

class AuthRemoteDataSource {
  final ApiClient _apiClient;

  AuthRemoteDataSource(this._apiClient);

  Future<Map<String, dynamic>> registerClient({
    required String email,
    String? referralCode,
  }) async {
    try {
      final json = await _apiClient.post(
        AppConstants.registerEndpoint,
        data: {
          'email': email,
          if (referralCode != null) 'referral_code': referralCode,
        },
      );
      return json;
    } on AuthException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  Future<Map<String, dynamic>> loginClient(String email) async {
    try {
      final json = await _apiClient.post(
        AppConstants.loginEndpoint,
        data: {'email': email},
      );
      return json;
    } on AuthException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }
}
