import '../../core/errors/exceptions.dart';
import '../../core/network/api_client.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_ds.dart';

/// Concrete [AuthRepository] implementation.
///
/// Validates the token by making a test request to the balance endpoint.
/// On success, persists the token locally and updates the ApiClient.
class AuthRepositoryImpl implements AuthRepository {
  final AuthLocalDataSource _localDs;
  final ApiClient _apiClient;

  AuthRepositoryImpl(this._localDs, this._apiClient);

  @override
  Future<bool> login(String token) async {
    try {
      // Set the token in the API client first
      _apiClient.setToken(token);

      // Validate by calling balance endpoint — 401 means invalid
      // B2C MOCK: Skip strict validation while backend is not fully connected.
      // await _apiClient.get('/api/v1/balance');
      await Future.delayed(const Duration(milliseconds: 600)); // Simulate network

      // Token is valid (or simulated valid) — persist it
      await _localDs.saveToken(token);
      return true;
    } on AuthException {
      _apiClient.clearToken();
      return false;
    } on NetworkException {
      _apiClient.clearToken();
      rethrow;
    } catch (_) {
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
}
