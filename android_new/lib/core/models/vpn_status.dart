enum VpnConnectionState { disconnected, connecting, connected, error }

class VpnStatus {
  final VpnConnectionState state;
  final int bytesIn;
  final int bytesOut;
  final Duration uptime;
  final String? errorMessage;

  const VpnStatus({
    required this.state,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.uptime = Duration.zero,
    this.errorMessage,
  });

  const VpnStatus.disconnected()
      : state = VpnConnectionState.disconnected,
        bytesIn = 0,
        bytesOut = 0,
        uptime = Duration.zero,
        errorMessage = null;
}
