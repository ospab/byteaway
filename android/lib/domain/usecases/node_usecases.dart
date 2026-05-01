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
    String? transportMode,
    String? connType,
    int? speedMbps,
    int? mtu,
    String? masterWsUrl,

  }) {
    return _repository.startNode(
      token: token,
      deviceId: deviceId,
      country: country,
      transportMode: transportMode,
      connType: connType,
      speedMbps: speedMbps,
      mtu: mtu,
      masterWsUrl: masterWsUrl,

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
