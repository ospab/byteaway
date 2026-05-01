import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/datasources/auth_local_ds.dart';
import 'settings_state.dart';

/// Cubit managing sharing settings: speed limit, WiFi-only, mobile data.
class SettingsCubit extends Cubit<SettingsState> {
  final AuthLocalDataSource _localDs;

  SettingsCubit(this._localDs) : super(const SettingsState()) {
    _loadSettings();
  }

  void _loadSettings() {
    emit(SettingsState(
      speedLimitMbps: _localDs.getSpeedLimit(),
      wifiOnly: _localDs.getWifiOnly(),
      allowMobileData: _localDs.getAllowMobile(),
      killSwitch: _localDs.getKillSwitch(),
      nodeTransportMode: _localDs.getNodeTransportMode(),
      vpnMtu: _localDs.getVpnMtu(),
      showVpnButton: _localDs.getShowVpnButton(),
      vpnProtocol: _localDs.getVpnProtocol(),
    ));
  }

  /// Update speed limit (1–100 Mbps).
  Future<void> setSpeedLimit(int mbps) async {
    final clamped = mbps.clamp(1, 100);
    await _localDs.setSpeedLimit(clamped);
    emit(state.copyWith(speedLimitMbps: clamped));
  }

  /// Toggle mobile data sharing.
  Future<void> toggleMobileData(bool allow) async {
    await _localDs.setAllowMobile(allow);
    emit(state.copyWith(allowMobileData: allow));
  }

  /// Toggle WiFi only sharing.
  Future<void> toggleWifiOnly(bool wifiOnly) async {
    await _localDs.setWifiOnly(wifiOnly);
    emit(state.copyWith(wifiOnly: wifiOnly));
  }

  /// Toggle Kill Switch for VPN security.
  Future<void> toggleKillSwitch(bool killSwitch) async {
    await _localDs.setKillSwitch(killSwitch);
    emit(state.copyWith(killSwitch: killSwitch));
  }

  /// Update hidden node transport mode (quic/ws/hy2).
  Future<void> setNodeTransportMode(String mode) async {
    await _localDs.setNodeTransportMode(mode);
    emit(state.copyWith(nodeTransportMode: _localDs.getNodeTransportMode()));
  }

  /// Update VPN MTU setting.
  Future<void> setVpnMtu(int mtu) async {
    await _localDs.setVpnMtu(mtu);
    emit(state.copyWith(vpnMtu: _localDs.getVpnMtu()));
  }

  /// Toggle debug VPN button visibility on home screen.
  Future<void> toggleShowVpnButton(bool show) async {
    await _localDs.setShowVpnButton(show);
    emit(state.copyWith(showVpnButton: show));
  }

  /// Toggle VPN protocol.
  Future<void> setVpnProtocol(String protocol) async {
    await _localDs.setVpnProtocol(protocol);
    emit(state.copyWith(vpnProtocol: protocol));
  }
}
