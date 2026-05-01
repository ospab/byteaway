/// Abstract auth repository.
abstract class AuthRepository {
  /// Persist token locally and validate against server.
  Future<bool> login(String token);

  /// Remove stored token.
  Future<void> logout();

  /// Get stored token, null if not logged in.
  Future<String?> getStoredToken();

  /// Check if a valid token exists.
  Future<bool> isLoggedIn();

  /// Register new client with email
  Future<Map<String, dynamic>> register(String email, {String? referralCode});

  /// Login with email (get token)
  Future<Map<String, dynamic>> loginWithEmail(String email);
}
