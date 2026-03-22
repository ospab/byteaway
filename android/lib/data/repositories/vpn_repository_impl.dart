import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/repositories/vpn_repository.dart';

/// Concrete [VpnRepository] — manages sing-box VPN via Platform Channel.
///
/// All VPN operations delegate to the Kotlin Foreground Service through
/// MethodChannel. Status updates are received via EventChannel.
class VpnRepositoryImpl implements VpnRepository {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  StreamSubscription? _subscription;
  final _statusController = StreamController<VpnStatus>.broadcast();

  VpnRepositoryImpl()
      : _methodChannel = const MethodChannel(AppConstants.serviceChannel),
        _eventChannel = const EventChannel(AppConstants.serviceEventsChannel) {
    _listenToEvents();
  }

  @override
  Future<bool> connect(String config) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startVpn',
        {'config': config},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopVpn');
      return result ?? false;
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
          _statusController.add(_mapToVpnStatus(event));
        }
      },
      onError: (error) {
        _statusController.add(VpnStatus(
          state: VpnConnectionState.error,
          errorMessage: error.toString(),
        ));
      },
    );
  }

  VpnStatus _mapToVpnStatus(Map<dynamic, dynamic> map) {
    final connected = map['vpnConnected'] as bool? ?? false;
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

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}
