/// API and WebSocket URLs, shared application constants.
class AppConstants {
  AppConstants._();

  // ── Master Node ──────────────────────────────────────────
  static const String baseUrl = 'https://byteaway.ospab.host';
  static const String wsUrl = 'wss://byteaway.ospab.host/ws';

  // REST endpoints
  static const String balanceEndpoint = '/api/v1/balance';
  static const String proxiesEndpoint = '/api/v1/proxies';
  static const String statsEndpoint = '/api/v1/stats';

  // ── Platform Channel ─────────────────────────────────────
  static const String serviceChannel = 'com.byteaway.service';
  static const String serviceEventsChannel = 'com.byteaway.service/events';

  // ── Defaults ─────────────────────────────────────────────
  static const int defaultSpeedLimitMbps = 50;
  static const int heartbeatIntervalSec = 30;
  static const int wsReconnectDelaySec = 5;

  // ── Storage Keys ─────────────────────────────────────────
  static const String tokenKey = 'auth_token';
  static const String deviceIdKey = 'device_id';
  static const String speedLimitKey = 'speed_limit_mbps';
  static const String allowMobileKey = 'allow_mobile_data';
}
