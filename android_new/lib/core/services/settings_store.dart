import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _protocolKey = 'vpn_protocol';
  static const _mtuKey = 'vpn_mtu';
  static const _killSwitchKey = 'kill_switch';
  static const _ostpHostKey = 'ostp_host';
  static const _ostpPortKey = 'ostp_port';
  static const _ostpLocalPortKey = 'ostp_local_port';
  static const _countryKey = 'country_code';
  static const _connTypeKey = 'conn_type';

  final SharedPreferences prefs;

  SettingsStore(this.prefs);

  String get protocol => prefs.getString(_protocolKey) ?? 'vless';
  Future<void> setProtocol(String value) => prefs.setString(_protocolKey, value);

  int get mtu => prefs.getInt(_mtuKey) ?? 1500;
  Future<void> setMtu(int value) => prefs.setInt(_mtuKey, value);

  bool get killSwitch => prefs.getBool(_killSwitchKey) ?? false;
  Future<void> setKillSwitch(bool value) => prefs.setBool(_killSwitchKey, value);

  String get ostpHost => prefs.getString(_ostpHostKey) ?? 'byteaway.xyz';
  Future<void> setOstpHost(String value) => prefs.setString(_ostpHostKey, value);

  int get ostpPort => prefs.getInt(_ostpPortKey) ?? 8443;
  Future<void> setOstpPort(int value) => prefs.setInt(_ostpPortKey, value);

  int get ostpLocalPort => prefs.getInt(_ostpLocalPortKey) ?? 1088;
  Future<void> setOstpLocalPort(int value) => prefs.setInt(_ostpLocalPortKey, value);

  String get country => prefs.getString(_countryKey) ?? 'RU';
  Future<void> setCountry(String value) => prefs.setString(_countryKey, value);

  String get connType => prefs.getString(_connTypeKey) ?? 'wifi';
  Future<void> setConnType(String value) => prefs.setString(_connTypeKey, value);
}
