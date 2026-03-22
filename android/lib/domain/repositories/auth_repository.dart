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
}
