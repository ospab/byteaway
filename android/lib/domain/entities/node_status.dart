import 'package:equatable/equatable.dart';

/// Node (traffic sharing) state.
enum NodeConnectionState {
  inactive,
  connecting,
  active,         // WebSocket connected, sharing traffic
  conditionWait,  // Waiting for WiFi + charging
  error,
}

/// Full node status including traffic counters.
class NodeStatus extends Equatable {
  final NodeConnectionState state;
  final int totalBytesShared;
  final double currentSpeedMbps;
  final int activeSessions;
  final Duration uptime;
  final String? errorMessage;

  const NodeStatus({
    required this.state,
    this.totalBytesShared = 0,
    this.currentSpeedMbps = 0,
    this.activeSessions = 0,
    this.uptime = Duration.zero,
    this.errorMessage,
  });

  const NodeStatus.inactive()
      : state = NodeConnectionState.inactive,
        totalBytesShared = 0,
        currentSpeedMbps = 0,
        activeSessions = 0,
        uptime = Duration.zero,
        errorMessage = null;

  double get totalSharedGb => totalBytesShared / 1073741824.0;
  bool get isActive => state == NodeConnectionState.active;

  @override
  List<Object?> get props =>
      [state, totalBytesShared, currentSpeedMbps, activeSessions, uptime, errorMessage];
}
