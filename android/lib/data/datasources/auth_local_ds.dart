import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
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

  /// Get or generate persistent device ID (UUID v4).
  String getDeviceId() {
    var id = _prefs.getString(AppConstants.deviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(AppConstants.deviceIdKey, id);
    }
    return id;
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

  /// Check if mobile data sharing is allowed.
  bool getAllowMobile() {
    return _prefs.getBool(AppConstants.allowMobileKey) ?? false;
  }

  /// Save mobile data sharing setting.
  Future<void> setAllowMobile(bool allow) async {
    await _prefs.setBool(AppConstants.allowMobileKey, allow);
  }
}
