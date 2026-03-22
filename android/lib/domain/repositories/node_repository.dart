import '../entities/node_status.dart';

/// Abstract node repository — manages traffic sharing node lifecycle.
abstract class NodeRepository {
  /// Start sharing: register with master node over WebSocket.
  Future<bool> startNode({
    required String token,
    required String deviceId,
    required String country,
    int? speedMbps,
  });

  /// Stop sharing: disconnect from master node.
  Future<bool> stopNode();

  /// Get current node status.
  Future<NodeStatus> getStatus();

  /// Stream of node status changes (EventChannel from Foreground Service).
  Stream<NodeStatus> get statusStream;
}
