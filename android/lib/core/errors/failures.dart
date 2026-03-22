import 'package:equatable/equatable.dart';

/// Sealed failure hierarchy for domain-level error handling.
/// Each failure carries an optional [message] for UI display.
sealed class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

/// Network unreachable or timeout.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Нет подключения к сети']);
}

/// HTTP 4xx / 5xx from master node.
class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure({String message = 'Ошибка сервера', this.statusCode})
      : super(message);

  @override
  List<Object?> get props => [message, statusCode];
}

/// Auth token invalid or expired.
class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Неавторизован']);
}

/// Platform channel call failed.
class PlatformFailure extends Failure {
  const PlatformFailure([super.message = 'Ошибка нативного сервиса']);
}

/// WebSocket connection error.
class WebSocketFailure extends Failure {
  const WebSocketFailure([super.message = 'Ошибка WebSocket соединения']);
}

/// Generic / unexpected error.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'Непредвиденная ошибка']);
}
