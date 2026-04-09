import '../../domain/entities/node_status.dart';

/// JSON-serializable node status model.
/// Maps from native EventChannel data and REST API responses.
class NodeStatusModel {
  final String state;
  final int totalBytesShared;
  final double currentSpeedMbps;
  final int activeSessions;
  final int uptimeSeconds;
  final String? errorMessage;

  const NodeStatusModel({
    required this.state,
    this.totalBytesShared = 0,
    this.currentSpeedMbps = 0,
    this.activeSessions = 0,
    this.uptimeSeconds = 0,
    this.errorMessage,
  });

  factory NodeStatusModel.fromJson(Map<String, dynamic> json) {
    return NodeStatusModel(
      state: json['state'] as String? ?? 'inactive',
      totalBytesShared: json['total_bytes_shared'] as int? ?? 0,
      currentSpeedMbps: (json['current_speed_mbps'] as num?)?.toDouble() ?? 0,
      activeSessions: json['active_sessions'] as int? ?? 0,
      uptimeSeconds: json['uptime_seconds'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
    );
  }

  /// Map from platform channel data (camelCase keys).
  factory NodeStatusModel.fromPlatform(Map<dynamic, dynamic> map) {
    final nodeActive = map['nodeActive'] == true;
    final nodeConnecting = map['nodeConnecting'] == true;
    final state = nodeActive ? 'active' : (nodeConnecting ? 'connecting' : 'inactive');
    final nodeError = (map['nodeErrorMessage'] as String?)?.trim();
    final genericError = (map['errorMessage'] as String?)?.trim();

    return NodeStatusModel(
      state: state,
      totalBytesShared: map['bytesShared'] as int? ?? 0,
      currentSpeedMbps: (map['currentSpeed'] as num?)?.toDouble() ?? 0,
      activeSessions: map['activeSessions'] as int? ?? 0,
      uptimeSeconds: map['uptime'] as int? ?? 0,
      errorMessage: (nodeError != null && nodeError.isNotEmpty)
          ? nodeError
          : ((genericError != null && genericError.isNotEmpty) ? genericError : null),
    );
  }

  /// Convert to domain entity.
  NodeStatus toEntity() => NodeStatus(
        state: _parseState(state),
        totalBytesShared: totalBytesShared,
        currentSpeedMbps: currentSpeedMbps,
        activeSessions: activeSessions,
        uptime: Duration(seconds: uptimeSeconds),
        errorMessage: errorMessage,
      );

  static NodeConnectionState _parseState(String s) {
    switch (s) {
      case 'active':
        return NodeConnectionState.active;
      case 'connecting':
        return NodeConnectionState.connecting;
      case 'condition_wait':
        return NodeConnectionState.conditionWait;
      case 'error':
        return NodeConnectionState.error;
      default:
        return NodeConnectionState.inactive;
    }
  }
}
