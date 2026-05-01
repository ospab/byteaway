/// API and WebSocket URLs, shared application constants.
class AppConstants {
  AppConstants._();

  // ── Base URLs ──
  static const String baseUrl = 'https://byteaway.xyz';
  static const String wsUrl = 'wss://byteaway.xyz/ws';
  static const String apiBaseUrl = '$baseUrl/api/v1';
  static const String updateManifestUrl = '$apiBaseUrl/app/update/manifest';

  // ── VPN ──
  static const String vpnConfigUrl = '$apiBaseUrl/vpn/config';
  static const String vpnProtocol = 'vless';

  // ── DNS ──
  static const List<String> dnsServers = [
    '1.1.1.1',
    '1.0.0.1',
    '8.8.8.8',
    '9.9.9.9',
  ];

  // ── Network ──
  static const int defaultVpnMtu = 1280;
  static const int minVpnMtu = 1280;
  static const int maxVpnMtu = 1480;
  static const int connectionTimeout = 30;
  static const int reconnectInterval = 5;

  // ── App ──
  static const String appName = 'ByteAway';
  static const String appVersion = '1.0.186';
  static const int appBuildNumber = 232;
  static const bool isDevelopment = false;

  // ── REST Endpoints ──
  static const String balanceEndpoint = '/api/v1/balance';
  static const String proxiesEndpoint = '/api/v1/proxies';
  static const String statsEndpoint = '/api/v1/stats';
  static const String registerEndpoint = '/api/v1/register';
  static const String loginEndpoint = '/api/v1/login';

  // ── Platform Channels ──
  static const String serviceChannel = 'com.byteaway.service';
  static const String serviceEventsChannel = 'com.byteaway.service/events';
  static const String updaterChannel = 'com.ospab.byteaway/updater';

  // ── Node Defaults ──
  static const int defaultSpeedLimitMbps = 50;
  static const int heartbeatIntervalSec = 30;
  static const int wsReconnectDelaySec = 5;

  // ── SharedPreferences Keys ──
  static const String tokenKey = 'auth_token';
  static const String deviceIdKey = 'device_id';
  static const String speedLimitKey = 'speed_limit_mbps';
  static const String vpnMtuKey = 'vpn_mtu';
  static const String nodeTransportModeKey = 'node_transport_mode';
  static const String allowMobileKey = 'allow_mobile_data';
  static const String wifiOnlyKey = 'wifi_only_sharing';
  static const String killSwitchKey = 'kill_switch_enabled';
  static const String onboardingDoneKey = 'onboarding_done';
  static const String showVpnButtonKey = 'show_vpn_button';
  static const String vpnProtocolKey = 'vpn_protocol';
}

















