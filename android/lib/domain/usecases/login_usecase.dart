import '../repositories/auth_repository.dart';

/// Authenticate user with API token.
///
/// Stores token locally and validates it against the master node.
class LoginUseCase {
  final AuthRepository _repository;

  const LoginUseCase(this._repository);

  /// Returns `true` if the token is valid and has been saved.
  Future<bool> call(String token) async {
    if (token.trim().isEmpty) {
      return false;
    }
    return _repository.login(token.trim());
  }
}
