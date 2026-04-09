import '../entities/vpn_status.dart';

/// Abstract VPN repository — manages sing-box VPN lifecycle via platform channel.
abstract class VpnRepository {
  /// Connect VPN using sing-box. [config] is the sing-box JSON config.
  Future<bool> connect(String config);

  /// Disconnect VPN.
  Future<bool> disconnect();

  /// Get current VPN status from native side.
  Future<VpnStatus> getStatus();

  /// Get VLESS configuration from master node with tier info.
  Future<Map<String, dynamic>> getVpnConfig({bool useRuEgress = false});

  /// Stream of VPN status changes from EventChannel.
  Stream<VpnStatus> get statusStream;
}
