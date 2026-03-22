import '../repositories/node_repository.dart';

/// Start sharing traffic as a node — register with master via WebSocket.
class StartNodeUseCase {
  final NodeRepository _repository;

  const StartNodeUseCase(this._repository);

  /// Start node sharing. Requires WiFi + charging conditions to be met.
  Future<bool> call({
    required String token,
    required String deviceId,
    required String country,
    int? speedMbps,
  }) {
    return _repository.startNode(
      token: token,
      deviceId: deviceId,
      country: country,
      speedMbps: speedMbps,
    );
  }
}

/// Stop sharing traffic — disconnect node from master.
class StopNodeUseCase {
  final NodeRepository _repository;

  const StopNodeUseCase(this._repository);

  Future<bool> call() {
    return _repository.stopNode();
  }
}
