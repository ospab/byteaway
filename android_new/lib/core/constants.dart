class AppConstants {
  AppConstants._();

  static const String baseUrl = 'https://byteaway.xyz';
  static const String apiBase = 'https://byteaway.xyz/api/v1';
  
  static const String vpnConfigEndpoint = '/api/v1/vpn/config';
  static const String balanceEndpoint = '/api/v1/balance';
  static const String statsEndpoint = '/api/v1/stats';
  static const String registerNodeEndpoint = '/api/v1/auth/register-node';
  static const String updateManifestUrl = 'https://byteaway.xyz/api/v1/app/update/manifest';
  static const String updateApkUrl = 'https://byteaway.xyz/api/v1/app/update/apk';

  static const String ostpHost = 'byteaway.xyz';
  static const int ostpPort = 8443;
  static const int ostpLocalPort = 1088;

  static const String serviceChannel = 'com.byteaway.service';
  static const String serviceEventsChannel = 'com.byteaway.service/events';
  static const String splitTunnelChannel = 'com.ospab.byteaway/app';
  static const String deviceChannel = 'com.ospab.byteaway/device';
  static const String updaterChannel = 'com.ospab.byteaway/updater';

  static const int freeDailyLimitBytes = 5368709120; // 5 GB
}








