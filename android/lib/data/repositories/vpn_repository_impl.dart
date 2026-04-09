import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/network/api_client.dart';
import '../datasources/auth_local_ds.dart';
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
  final AuthLocalDataSource _authLocalDs;
  StreamSubscription? _subscription;
  final _statusController = StreamController<VpnStatus>.broadcast();
  Timer? _statusPollTimer;
  VpnStatus? _lastEmittedStatus;

  VpnRepositoryImpl(this._apiClient, this._authLocalDs)
      : _methodChannel = const MethodChannel(AppConstants.serviceChannel),
        _eventChannel = const EventChannel(AppConstants.serviceEventsChannel) {
    _listenToEvents();
    _startStatusPolling();
  }

  @override
  Future<Map<String, dynamic>> getVpnConfig({bool useRuEgress = false}) async {
    final suffix = useRuEgress ? '?use_ru_egress=1' : '';
    final response = await _apiClient.get('/api/v1/vpn/config$suffix');
    // Ensure compatibility if server is not yet updated, but we transition to core_config_json
    if (response.containsKey('core_config_json')) {
      return response;
    } else if (response.containsKey('xray_config_json')) {
      final map = Map<String, dynamic>.from(response);
      map['core_config_json'] = map['xray_config_json'];
      return map;
    }
    return response;
  }

  @override
  Future<bool> connect(String config) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startVpn',
        {
          'config': config,
          'mtu': _authLocalDs.getVpnMtu(),
        },
      );
      final success = result ?? false;
      if (success) {
        _emitStatus(const VpnStatus(state: VpnConnectionState.connecting));
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
        _emitStatus(const VpnStatus(state: VpnConnectionState.disconnected));
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
        if (event is Map) {
          final nativeLog = (event['nativeLog'] as String?)?.trim();
          if (nativeLog != null && nativeLog.isNotEmpty) {
            AppLogger.log('native: $nativeLog');
          }
          _emitStatus(_mapToVpnStatus(event));
        }
      },
      onError: (error) {
        _emitStatus(VpnStatus(
          state: VpnConnectionState.error,
          errorMessage: error.toString(),
        ));
      },
    );
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final result = await _methodChannel.invokeMethod<Map>('getStatus');
        if (result != null) {
          _emitStatus(_mapToVpnStatus(result));
        }
      } catch (_) {}
    });
  }

  void _emitStatus(VpnStatus status) {
    if (_lastEmittedStatus == status) return;
    _lastEmittedStatus = status;
    _statusController.add(status);
  }

  VpnStatus _mapToVpnStatus(Map<dynamic, dynamic> map) {
    final connected = map['vpnConnected'] as bool? ?? false;
    final connecting = map['vpnConnecting'] as bool? ?? false;
    final errorMessage = (map['errorMessage'] as String?)?.trim();

    if (!connected && !connecting && errorMessage != null && errorMessage.isNotEmpty) {
      return VpnStatus(
        state: VpnConnectionState.error,
        errorMessage: errorMessage,
      );
    }

    VpnConnectionState state = VpnConnectionState.disconnected;
    if (connected) {
      state = VpnConnectionState.connected;
    } else if (connecting) {
      state = VpnConnectionState.connecting;
    }

    return VpnStatus(
      state: state,
      serverAddress: map['serverAddress'] as String?,
      uptime: Duration(seconds: map['uptime'] as int? ?? 0),
      bytesIn: map['bytesIn'] as int? ?? 0,
      bytesOut: map['bytesOut'] as int? ?? 0,
    );
  }

  void dispose() {
    _statusPollTimer?.cancel();
    _subscription?.cancel();
    _statusController.close();
  }
}
