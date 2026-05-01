import '../../core/errors/exceptions.dart';
import '../../core/logger.dart';
import '../../core/network/api_client.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_ds.dart';
import '../datasources/auth_remote_ds.dart';

/// Concrete [AuthRepository] implementation.
///
/// Validates the token by making a test request to the balance endpoint.
/// On success, persists the token locally and updates the ApiClient.
class AuthRepositoryImpl implements AuthRepository {
  final AuthLocalDataSource _localDs;
  final AuthRemoteDataSource _remoteDs;
  final ApiClient _apiClient;

  AuthRepositoryImpl(this._localDs, this._remoteDs, this._apiClient);

  @override
  Future<bool> login(String token) async {
    try {
      AppLogger.log(
          'auth.login register-node request device_id_len=${token.length}');
      // For B2C we first register by device_id and then use issued token when available.
      final response = await _apiClient.post(
        '/api/v1/auth/register-node',
        data: {'device_id': token},
      );

      // Registration is successful when node_id is returned.
      if (response.containsKey('node_id')) {
        final issuedToken = (response['token'] as String?)?.trim();
        // Prefer server-issued token; fallback keeps legacy compatibility.
        final bearer = (issuedToken != null && issuedToken.isNotEmpty)
            ? issuedToken
            : token;
        AppLogger.log(
          'auth.login success node_id_present=true issued_token_present=${issuedToken != null && issuedToken.isNotEmpty}',
        );
        _apiClient.setToken(bearer);
        await _localDs.saveToken(bearer);

        // Register device with HWID
        try {
          final hwid = await _localDs.getDeviceId();
          final deviceResponse = await _apiClient.post(
            '/api/v1/register-device',
            data: {
              'hwid': hwid,
              'device_name': 'Android',
              'os_type': 'android',
              'os_version': 'unknown',
              'app_version': '1.0.0',
            },
          );
          AppLogger.log(
              'auth.register-device success: is_new=${deviceResponse['is_new'] ?? false}');
        } catch (e) {
          AppLogger.log('auth.register-device failed: $e');
          // Continue without device registration if it fails
        }

        return true;
      }

      AppLogger.log(
          'auth.login failed: register-node response missing node_id');

      return false;
    } on AuthException {
      AppLogger.log('auth.login auth_exception');
      _apiClient.clearToken();
      return false;
    } on NetworkException {
      AppLogger.log('auth.login network_exception');
      _apiClient.clearToken();
      rethrow;
    } catch (e) {
      AppLogger.log('auth.login error=$e');
      _apiClient.clearToken();
      return false;
    }
  }

  @override
  Future<void> logout() async {
    await _localDs.removeToken();
    _apiClient.clearToken();
  }

  @override
  Future<String?> getStoredToken() async {
    return _localDs.getToken();
  }

  @override
  Future<bool> isLoggedIn() async {
    final token = _localDs.getToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<Map<String, dynamic>> register(String email,
      {String? referralCode}) async {
    return await _remoteDs.registerClient(
        email: email, referralCode: referralCode);
  }

  @override
  Future<Map<String, dynamic>> loginWithEmail(String email) async {
    return await _remoteDs.loginClient(email);
  }
}
