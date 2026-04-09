import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/errors/exceptions.dart';

/// Local data source for auth token and device identity.
/// Uses SharedPreferences for persistence.
class AuthLocalDataSource {
  final SharedPreferences _prefs;

  AuthLocalDataSource(this._prefs);

  /// Save auth token.
  Future<void> saveToken(String token) async {
    final saved = await _prefs.setString(AppConstants.tokenKey, token);
    if (!saved) throw const CacheException('Не удалось сохранить токен');
  }

  /// Get stored token, returns null if none.
  String? getToken() {
    return _prefs.getString(AppConstants.tokenKey);
  }

  /// Remove stored token.
  Future<void> removeToken() async {
    await _prefs.remove(AppConstants.tokenKey);
  }

  /// Get persisted device ID (HWID). Returns null if missing.
  String? getDeviceId() {
    final id = _prefs.getString(AppConstants.deviceIdKey);
    if (id == null || id.trim().isEmpty) {
      return null;
    }
    return id;
  }

  /// Persist externally provided hardware ID.
  Future<void> saveDeviceId(String deviceId) async {
    final saved = await _prefs.setString(AppConstants.deviceIdKey, deviceId);
    if (!saved) throw const CacheException('Не удалось сохранить device_id');
  }

  /// Get speed limit setting (Mbps).
  int getSpeedLimit() {
    return _prefs.getInt(AppConstants.speedLimitKey) ??
        AppConstants.defaultSpeedLimitMbps;
  }

  /// Save speed limit setting.
  Future<void> setSpeedLimit(int mbps) async {
    await _prefs.setInt(AppConstants.speedLimitKey, mbps);
  }

  /// Get VPN MTU setting.
  int getVpnMtu() {
    final value = _prefs.getInt(AppConstants.vpnMtuKey) ?? AppConstants.defaultVpnMtu;
    return value.clamp(AppConstants.minVpnMtu, AppConstants.maxVpnMtu);
  }

  /// Save VPN MTU setting.
  Future<void> setVpnMtu(int mtu) async {
    final safe = mtu.clamp(AppConstants.minVpnMtu, AppConstants.maxVpnMtu);
    await _prefs.setInt(AppConstants.vpnMtuKey, safe);
  }

  /// Get hidden node transport mode (quic/ws/hy2).
  String getNodeTransportMode() {
    final mode = _prefs.getString(AppConstants.nodeTransportModeKey) ?? 'quic';
    final normalized = mode.trim().toLowerCase();
    if (normalized == 'ws' || normalized == 'hy2' || normalized == 'quic') {
      return normalized;
    }
    return 'quic';
  }

  /// Save hidden node transport mode (quic/ws/hy2).
  Future<void> setNodeTransportMode(String mode) async {
    final normalized = mode.trim().toLowerCase();
    final safe = (normalized == 'ws' || normalized == 'hy2' || normalized == 'quic')
        ? normalized
        : 'quic';
    await _prefs.setString(AppConstants.nodeTransportModeKey, safe);
  }

  /// Check if mobile data sharing is allowed.
  bool getAllowMobile() {
    return _prefs.getBool(AppConstants.allowMobileKey) ?? false;
  }

  /// Save mobile data sharing setting.
  Future<void> setAllowMobile(bool allow) async {
    await _prefs.setBool(AppConstants.allowMobileKey, allow);
  }

  /// Get WiFi only sharing setting.
  bool getWifiOnly() {
    return _prefs.getBool(AppConstants.wifiOnlyKey) ?? true;
  }

  /// Save WiFi only sharing setting.
  Future<void> setWifiOnly(bool wifiOnly) async {
    await _prefs.setBool(AppConstants.wifiOnlyKey, wifiOnly);
  }

  /// Get Kill Switch setting.
  bool getKillSwitch() {
    return _prefs.getBool(AppConstants.killSwitchKey) ?? false;
  }

  /// Save Kill Switch setting.
  Future<void> setKillSwitch(bool killSwitch) async {
    await _prefs.setBool(AppConstants.killSwitchKey, killSwitch);
  }
}
