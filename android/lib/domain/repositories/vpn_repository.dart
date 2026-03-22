import '../entities/vpn_status.dart';

/// Abstract VPN repository — manages sing-box VPN lifecycle via platform channel.
abstract class VpnRepository {
  /// Connect VPN using sing-box. [config] is the sing-box JSON config.
  Future<bool> connect(String config);

  /// Disconnect VPN.
  Future<bool> disconnect();

  /// Get current VPN status from native side.
  Future<VpnStatus> getStatus();

  /// Stream of VPN status changes from EventChannel.
  Stream<VpnStatus> get statusStream;
}
