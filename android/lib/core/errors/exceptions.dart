/// Custom exceptions thrown in the data layer.
/// These are caught and mapped to [Failure] in repositories.

class ServerException implements Exception {
  final String message;
  final int? statusCode;
  const ServerException({this.message = 'Server error', this.statusCode});

  @override
  String toString() => 'ServerException($statusCode): $message';
}

class AuthException implements Exception {
  final String message;
  const AuthException([this.message = 'Unauthorized']);

  @override
  String toString() => 'AuthException: $message';
}

class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'Network unavailable']);

  @override
  String toString() => 'NetworkException: $message';
}

class CacheException implements Exception {
  final String message;
  const CacheException([this.message = 'Cache error']);

  @override
  String toString() => 'CacheException: $message';
}
