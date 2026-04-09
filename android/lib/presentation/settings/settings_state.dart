import 'package:equatable/equatable.dart';

/// Settings state.
class SettingsState extends Equatable {
  final int speedLimitMbps;
  final bool wifiOnly;
  final bool allowMobileData;
  final bool killSwitch;
  final String nodeTransportMode;
  final int vpnMtu;

  const SettingsState({
    this.speedLimitMbps = 50,
    this.wifiOnly = true,
    this.allowMobileData = false,
    this.killSwitch = false,
    this.nodeTransportMode = 'quic',
    this.vpnMtu = 1280,
  });

  SettingsState copyWith({
    int? speedLimitMbps,
    bool? wifiOnly,
    bool? allowMobileData,
    bool? killSwitch,
    String? nodeTransportMode,
    int? vpnMtu,
  }) {
    return SettingsState(
      speedLimitMbps: speedLimitMbps ?? this.speedLimitMbps,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      allowMobileData: allowMobileData ?? this.allowMobileData,
      killSwitch: killSwitch ?? this.killSwitch,
      nodeTransportMode: nodeTransportMode ?? this.nodeTransportMode,
      vpnMtu: vpnMtu ?? this.vpnMtu,
    );
  }

  @override
  List<Object?> get props => [speedLimitMbps, wifiOnly, allowMobileData, killSwitch, nodeTransportMode, vpnMtu];
}
