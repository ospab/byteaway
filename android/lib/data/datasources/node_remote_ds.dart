import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
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
    int? speedMbps,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startNode',
        {
          'token': token,
          'deviceId': deviceId,
          'country': country,
          'speedMbps': speedMbps ?? AppConstants.defaultSpeedLimitMbps,
        },
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Stop sharing.
  Future<bool> stopNode() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopNode');
      return result ?? false;
    } on PlatformException {
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
      return const NodeStatusModel(state: 'inactive');
    } on PlatformException {
      return const NodeStatusModel(state: 'error', errorMessage: 'Ошибка нативного сервиса');
    }
  }

  void _listenToEvents() {
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _statusController.add(NodeStatusModel.fromPlatform(event));
        }
      },
      onError: (error) {
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
