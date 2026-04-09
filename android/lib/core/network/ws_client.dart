import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants.dart';

/// Binary WebSocket client matching master_node wire protocol.
///
/// Frame format: `[1 byte: cmd][16 bytes: session_uuid][N bytes: payload]`
/// - `0x01` CMD_CONNECT — master → node: open tunnel to target_addr
/// - `0x02` CMD_DATA    — bidirectional: raw data
/// - `0x03` CMD_CLOSE   — bidirectional: close session
class WsClient {
  static const int cmdConnect = 0x01;
  static const int cmdData = 0x02;
  static const int cmdClose = 0x03;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  bool _isConnected = false;

  final _messageController = StreamController<WsFrame>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// Stream of decoded binary frames from the master node.
  Stream<WsFrame> get messages => _messageController.stream;

  /// Stream of connection state changes.
  Stream<bool> get connectionState => _connectionController.stream;

  bool get isConnected => _isConnected;

  /// Connect to master node WebSocket with node credentials.
  Future<void> connect({
    required String deviceId,
    required String token,
    required String country,
    int? speedMbps,
  }) async {
    final uri = Uri.parse(AppConstants.wsUrl).replace(
      queryParameters: {
        'device_id': deviceId,
        'token': token,
        'country': country,
        'conn_type': 'wifi',
        if (speedMbps != null) 'speed_mbps': speedMbps.toString(),
      },
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _isConnected = true;
      _connectionController.add(true);

      _subscription = _channel!.stream.listen(
        (data) {
          if (data is List<int>) {
            final frame = WsFrame.decode(Uint8List.fromList(data));
            if (frame != null) {
              _messageController.add(frame);
            }
          }
        },
        onError: (error) {
          _isConnected = false;
          _connectionController.add(false);
        },
        onDone: () {
          _isConnected = false;
          _connectionController.add(false);
        },
      );

      // Start heartbeat — keep alive every 30s via ping
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: AppConstants.heartbeatIntervalSec),
        (_) {
          if (_isConnected) {
            try {
              _channel?.sink.add(Uint8List(0)); // ping
            } catch (_) {}
          }
        },
      );
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      rethrow;
    }
  }

  /// Send a binary frame to the master node.
  void sendFrame(WsFrame frame) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(frame.encode());
    }
  }

  /// Send raw bytes (CMD_DATA) for a given session.
  void sendData(Uint8List sessionId, Uint8List payload) {
    sendFrame(WsFrame(cmd: cmdData, sessionId: sessionId, payload: payload));
  }

  /// Send CMD_CLOSE for a session.
  void sendClose(Uint8List sessionId) {
    sendFrame(WsFrame(cmd: cmdClose, sessionId: sessionId, payload: Uint8List(0)));
  }

  /// Disconnect from WebSocket.
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  /// Release all resources.
  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
  }
}

/// Decoded binary frame from the WebSocket wire protocol.
class WsFrame {
  final int cmd;
  final Uint8List sessionId; // 16 bytes UUID
  final Uint8List payload;

  const WsFrame({
    required this.cmd,
    required this.sessionId,
    required this.payload,
  });

  /// Encode frame to wire format: [1:cmd][16:session_id][N:payload]
  Uint8List encode() {
    final buffer = BytesBuilder(copy: false);
    buffer.addByte(cmd);
    buffer.add(sessionId);
    buffer.add(payload);
    return buffer.toBytes();
  }

  /// Decode wire format to [WsFrame]. Returns null if too short.
  static WsFrame? decode(Uint8List data) {
    if (data.length < 17) return null;
    return WsFrame(
      cmd: data[0],
      sessionId: Uint8List.fromList(data.sublist(1, 17)),
      payload: Uint8List.fromList(data.sublist(17)),
    );
  }

  @override
  String toString() =>
      'WsFrame(cmd=0x${cmd.toRadixString(16)}, session=$_hexId, payload=${payload.length}B)';

  String get _hexId =>
      sessionId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
