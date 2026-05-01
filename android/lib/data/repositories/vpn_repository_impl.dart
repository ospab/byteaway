import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/repositories/vpn_repository.dart';

/// Concrete [VpnRepository] — manages sing-box VPN via Platform Channel.
///
/// All VPN operations delegate to the Kotlin Foreground Service through
/// MethodChannel. Status updates are received via EventChannel.
class VpnRepositoryImpl implements VpnRepository {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final ApiClient _apiClient;
  StreamSubscription? _subscription;
  final _statusController = StreamController<VpnStatus>.broadcast();

  VpnRepositoryImpl(this._apiClient)
      : _methodChannel = const MethodChannel(AppConstants.serviceChannel),
        _eventChannel = const EventChannel(AppConstants.serviceEventsChannel) {
    _listenToEvents();
  }

  @override
  Future<Map<String, dynamic>> getVpnConfig({bool useRuEgress = false}) async {
    final response = await _apiClient.get(
      '/api/v1/vpn/config',
      queryParameters: {
        if (useRuEgress) 'use_ru_egress': '1',
      },
    );
    return response;
  }

  @override
  Future<bool> connect(String config) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startVpn',
        {'config': config},
      );
      final success = result ?? false;
      if (success) {
        _statusController
            .add(const VpnStatus(state: VpnConnectionState.connected));
      }
      return success;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopVpn');
      final success = result ?? false;
      if (success) {
        _statusController
            .add(const VpnStatus(state: VpnConnectionState.disconnected));
      }
      return success;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<VpnStatus> getStatus() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('getStatus');
      if (result != null) {
        return _mapToVpnStatus(result);
      }
      return const VpnStatus.disconnected();
    } on PlatformException {
      return const VpnStatus(
        state: VpnConnectionState.error,
        errorMessage: 'Ошибка нативного сервиса',
      );
    }
  }

  @override
  Stream<VpnStatus> get statusStream => _statusController.stream;

  void _listenToEvents() {
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        AppLogger.log('VPN event from native: $event');
        if (event is Map) {
          _statusController.add(_mapToVpnStatus(event));
        }
      },
      onError: (error) {
        AppLogger.log('VPN event error: $error');
        _statusController.add(VpnStatus(
          state: VpnConnectionState.error,
          errorMessage: error.toString(),
        ));
      },
    );
  }

  VpnStatus _mapToVpnStatus(Map<dynamic, dynamic> map) {
    final connected = map['vpnConnected'] as bool? ?? false;
    final errorMessage = (map['errorMessage'] as String?)?.trim();

    if (!connected && errorMessage != null && errorMessage.isNotEmpty) {
      return VpnStatus(
        state: VpnConnectionState.error,
        errorMessage: errorMessage,
      );
    }

    return VpnStatus(
      state: connected
          ? VpnConnectionState.connected
          : VpnConnectionState.disconnected,
      serverAddress: map['serverAddress'] as String?,
      uptime: Duration(seconds: map['uptime'] as int? ?? 0),
      bytesIn: map['bytesIn'] as int? ?? 0,
      bytesOut: map['bytesOut'] as int? ?? 0,
    );
  }

  @override
  Future<bool> connectOstp(String config) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startVpn',
        {'config': config},
      );
      final success = result ?? false;
      if (success) {
        _statusController
            .add(const VpnStatus(state: VpnConnectionState.connected));
      }
      return success;
    } on PlatformException {
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}
