import 'dart:async';
import 'package:flutter/services.dart';
import '../constants.dart';
import '../models/vpn_status.dart';

class VpnRepository {
  final MethodChannel _methodChannel = const MethodChannel(AppConstants.serviceChannel);
  final EventChannel _eventChannel = const EventChannel(AppConstants.serviceEventsChannel);
  StreamSubscription? _subscription;
  final _statusController = StreamController<VpnStatus>.broadcast();

  VpnRepository() {
    _listen();
  }

  Stream<VpnStatus> get statusStream => _statusController.stream;

  Future<bool> startVpn(Map<String, dynamic> payload) async {
    final ok = await _methodChannel.invokeMethod<bool>('startVpn', payload);
    return ok ?? false;
  }

  Future<bool> stopVpn() async {
    final ok = await _methodChannel.invokeMethod<bool>('stopVpn');
    return ok ?? false;
  }

  Future<VpnStatus> getStatus() async {
    final raw = await _methodChannel.invokeMethod<Map>('getStatus');
    if (raw == null) return const VpnStatus.disconnected();
    return _mapStatus(raw);
  }

  void _listen() {
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _statusController.add(_mapStatus(event));
        }
      },
      onError: (error) {
        _statusController.add(
          VpnStatus(
            state: VpnConnectionState.error,
            errorMessage: error.toString(),
          ),
        );
      },
    );
  }

  VpnStatus _mapStatus(Map<dynamic, dynamic> map) {
    final connected = map['vpnConnected'] as bool? ?? false;
    final connecting = map['vpnConnecting'] as bool? ?? false;
    final error = (map['errorMessage'] as String?)?.trim();

    if (error != null && error.isNotEmpty && !connected) {
      return VpnStatus(
        state: VpnConnectionState.error,
        errorMessage: error,
      );
    }

    if (connecting && !connected) {
      return const VpnStatus(state: VpnConnectionState.connecting);
    }

    return VpnStatus(
      state: connected ? VpnConnectionState.connected : VpnConnectionState.disconnected,
      bytesIn: (map['bytesIn'] as int?) ?? 0,
      bytesOut: (map['bytesOut'] as int?) ?? 0,
      uptime: Duration(seconds: (map['uptime'] as int?) ?? 0),
      errorMessage: error,
    );
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}
