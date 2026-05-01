import 'package:equatable/equatable.dart';

/// VPN connection state.
enum VpnConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// Full VPN status with metadata.
class VpnStatus extends Equatable {
  final VpnConnectionState state;
  final String? serverAddress;
  final Duration uptime;
  final int bytesIn;
  final int bytesOut;
  final String? errorMessage;

  const VpnStatus({
    required this.state,
    this.serverAddress,
    this.uptime = Duration.zero,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.errorMessage,
  });

  const VpnStatus.disconnected()
      : state = VpnConnectionState.disconnected,
        serverAddress = null,
        uptime = Duration.zero,
        bytesIn = 0,
        bytesOut = 0,
        errorMessage = null;

  bool get isActive => state == VpnConnectionState.connected;

  @override
  List<Object?> get props => [state, serverAddress, uptime, bytesIn, bytesOut, errorMessage];
}
