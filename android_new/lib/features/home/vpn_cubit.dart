import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/vpn_status.dart';
import '../../core/network/api_client.dart';
import '../../core/services/settings_store.dart';
import '../../core/services/vpn_repository.dart';
import '../../core/services/log_service.dart';
import '../../core/constants.dart';
import 'vpn_state.dart';

class VpnCubit extends Cubit<VpnState> {
  VpnCubit() : super(VpnState.initial()) {
    _listen();
  }

  final ApiClient _api = sl<ApiClient>();
  final VpnRepository _vpnRepo = sl<VpnRepository>();
  final SettingsStore _settings = sl<SettingsStore>();

  void _listen() {
    _vpnRepo.statusStream.listen((status) {
      emit(state.copyWith(status: status));
    });
  }

  Future<void> connect() async {
    if (state.status.state == VpnConnectionState.connecting ||
        state.status.state == VpnConnectionState.connected) {
      return;
    }

    emit(state.copyWith(status: const VpnStatus(state: VpnConnectionState.connecting)));

    try {
      final configJson = await _api.getJson(AppConstants.vpnConfigEndpoint);
      final config = VpnConfig.fromJson(configJson);
      final prefs = sl.get<SharedPreferences>();
      final token = prefs.getString('auth_token') ?? '';
      final deviceId = prefs.getString('device_id') ?? '';

      final payload = {
        'protocol': _settings.protocol,
        'vless_link': config.vlessLink,
        'assigned_ip': config.assignedIp,
        'subnet': config.subnet,
        'gateway': config.gateway,
        'dns': config.dns,
        'tier': config.tier,
        'max_speed_mbps': config.maxSpeedMbps,
        'mtu': _settings.mtu,
        'token': token,
        'device_id': deviceId,
        'country': _settings.country,
        'conn_type': _settings.connType,
        'ostp_host': _settings.ostpHost,
        'ostp_port': _settings.ostpPort,
        'ostp_local_port': _settings.ostpLocalPort,
        'hwid': deviceId,
      };

      final ok = await _vpnRepo.startVpn({'config': jsonEncode(payload)});
      if (!ok) {
        emit(state.copyWith(
          status: const VpnStatus(state: VpnConnectionState.error),
          message: 'Не удалось запустить VPN',
        ));
      }
    } catch (e) {
      await LogService.write('vpn.connect error: $e');
      emit(state.copyWith(
        status: const VpnStatus(state: VpnConnectionState.error),
        message: e.toString(),
      ));
    }
  }

  Future<void> disconnect() async {
    await _vpnRepo.stopVpn();
  }

  @override
  Future<void> close() {
    _vpnRepo.dispose();
    return super.close();
  }
}
