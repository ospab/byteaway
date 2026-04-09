import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../core/logger.dart';
import '../models/node_status_model.dart';

/// Data source that bridges Platform Channel events for node status.
///
/// Listens to the EventChannel from Kotlin Foreground Service
/// and converts native status maps to [NodeStatusModel].
class NodeRemoteDataSource {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  StreamSubscription? _subscription;
  final _statusController = StreamController<NodeStatusModel>.broadcast();

  NodeRemoteDataSource()
      : _methodChannel = const MethodChannel(AppConstants.serviceChannel),
        _eventChannel = const EventChannel(AppConstants.serviceEventsChannel) {
    _listenToEvents();
  }

  /// Stream of node status updates from native service.
  Stream<NodeStatusModel> get statusStream => _statusController.stream;

  /// Start sharing as a node.
  Future<bool> startNode({
    required String token,
    required String deviceId,
    required String country,
    String? transportMode,
    String? connType,
    int? speedMbps,
    int? mtu,
    String? masterWsUrl,
    String? coreConfigJson,
  }) async {
    final mode = transportMode ?? 'quic';
    final conn = connType ?? 'unknown';
    final speed = speedMbps ?? AppConstants.defaultSpeedLimitMbps;
    debugPrint('ByteAway [Node]: Requesting start sharing (transport: $mode, country: $country, connType: $conn, speed: $speed Mbps)');
    AppLogger.log('node.start request transport=$mode country=$country connType=$conn speed=${speed}Mbps');
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startNode',
        {
          'token': token,
          'deviceId': deviceId,
          'country': country,
          'transportMode': transportMode ?? 'quic',
          'connType': connType ?? 'unknown',
          'speedMbps': speedMbps ?? AppConstants.defaultSpeedLimitMbps,
          'mtu': mtu,
          'masterWsUrl': masterWsUrl,
          'coreConfigJson': coreConfigJson,
        },
      );
      final ok = result ?? false;
      AppLogger.log('node.start result=$ok transport=$mode country=$country connType=$conn');
      return ok;
    } on PlatformException catch (e) {
      AppLogger.log('node.start platform_error code=${e.code} message=${e.message ?? ""}');
      return false;
    } catch (e) {
      AppLogger.log('node.start error=$e');
      return false;
    }
  }

  /// Stop sharing.
  Future<bool> stopNode() async {
    try {
      AppLogger.log('node.stop request');
      final result = await _methodChannel.invokeMethod<bool>('stopNode');
      final ok = result ?? false;
      AppLogger.log('node.stop result=$ok');
      return ok;
    } on PlatformException catch (e) {
      AppLogger.log('node.stop platform_error code=${e.code} message=${e.message ?? ""}');
      return false;
    } catch (e) {
      AppLogger.log('node.stop error=$e');
      return false;
    }
  }

  /// Get current status snapshot from native.
  Future<NodeStatusModel> getStatus() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('getStatus');
      if (result != null) {
        return NodeStatusModel.fromPlatform(result);
      }
      AppLogger.log('node.status returned null map');
      return const NodeStatusModel(state: 'inactive');
    } on PlatformException catch (e) {
      AppLogger.log('node.status platform_error code=${e.code} message=${e.message ?? ""}');
      return const NodeStatusModel(state: 'error', errorMessage: 'Ошибка нативного сервиса');
    } catch (e) {
      AppLogger.log('node.status error=$e');
      return const NodeStatusModel(state: 'error', errorMessage: 'Ошибка нативного сервиса');
    }
  }

  void _listenToEvents() {
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final nativeLog = (event['nativeLog'] as String?)?.trim();
          if (nativeLog != null && nativeLog.isNotEmpty) {
            AppLogger.log('native: $nativeLog');
          }
          _statusController.add(NodeStatusModel.fromPlatform(event));
        }
      },
      onError: (error) {
        AppLogger.log('node.event stream_error=$error');
        _statusController.add(
          NodeStatusModel(state: 'error', errorMessage: error.toString()),
        );
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}
