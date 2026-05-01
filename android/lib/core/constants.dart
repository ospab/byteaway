/// API and WebSocket URLs, shared application constants.
class AppConstants {
  AppConstants._();

  // Production URLs
  static const String baseUrl = 'https://byteaway.xyz';
  static const String wsUrl = 'wss://byteaway.xyz/ws';
  static const String updateManifestUrl =
      'https://byteaway.xyz/api/v1/app/update/manifest';

  // Master Node Configuration
  static const String masterNodeHost = 'byteaway.xyz';
  static const int masterNodePort = 35600;
  static const String masterNodeApiUrl = 'https://byteaway.xyz/api/v1';

  // SOCKS5 Configuration for Node Sharing
  static const String socks5Host = 'byteaway.xyz';
  static const int socks5Port = 31280;

  // VPN Configuration
  static const String vpnApiUrl = 'https://byteaway.xyz/api/v1/vpn';
  static const String vpnConfigUrl = 'https://byteaway.xyz/api/v1/vpn/config';

  // DNS Servers
  static const List<String> dnsServers = [
    '1.1.1.1',
    '1.0.0.1',
    '8.8.8.8',
    '9.9.9.9',
    '77.88.8.8',
  ];

  // Network Configuration
  static const int mtuSize = 1280;
  static const int defaultVpnMtu = 1280;
  static const int minVpnMtu = 1280;
  static const int maxVpnMtu = 1480;
  static const int connectionTimeout = 30; // seconds
  static const int reconnectInterval = 5; // seconds

  // App Configuration
  static const String appName = 'ByteAway';
  static const String appVersion = '1.0.166';
  static const int appBuildNumber = 212;

  // Feature Flags
  static const bool enableDebugLogs = false;
  static const bool enableCrashReporting = true;
  static const bool enableAnalytics = true;

  // Rate Limiting
  static const int maxRetries = 3;
  static const int retryDelay = 1000; // milliseconds

  // Security
  static const bool enableCertificatePinning = true;
  static const bool enableApiTokenValidation = true;

  // VPN Protocol Configuration
  static const String vpnProtocol = 'vless';
  static const String vpnTransport = 'reality';
  static const String vpnSecurity = 'tls';

  // B2B Configuration
  static const String b2bApiUrl = 'https://byteaway.xyz/api/v1';
  static const String b2bBalanceEndpoint = '/balance';
  static const String b2bStatsEndpoint = '/stats';

  // Testing (remove in production)
  static const bool isDevelopment = false;
  static const String testApiKey = ''; // Remove in production

  // REST endpoints
  static const String balanceEndpoint = '/api/v1/balance';
  static const String proxiesEndpoint = '/api/v1/proxies';
  static const String statsEndpoint = '/api/v1/stats';
  static const String registerEndpoint = '/api/v1/register';
  static const String loginEndpoint = '/api/v1/login';

  // Platform Channel
  static const String serviceChannel = 'com.byteaway.service';
  static const String serviceEventsChannel = 'com.byteaway.service/events';
  static const String updaterChannel = 'com.ospab.byteaway/updater';

  // Defaults
  static const int defaultSpeedLimitMbps = 50;
  static const int heartbeatIntervalSec = 30;
  static const int wsReconnectDelaySec = 5;

  // Storage Keys
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



















































































