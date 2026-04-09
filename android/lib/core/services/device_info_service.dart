import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';

/// Service for getting device location and network info
class DeviceInfoService {
  static const MethodChannel _channel = MethodChannel('com.ospab.byteaway/device_info');

  /// Get country code from device (SIM or locale)
  static Future<String> getCountryCode() async {
    try {
      final String? country = await _channel.invokeMethod('getCountryCode');
      return country?.toUpperCase() ?? 'UNKNOWN';
    } catch (e) {
      // Fallback to locale
      final locale = PlatformDispatcher.instance.locale;
      return locale.countryCode?.toUpperCase() ?? 'UNKNOWN';
    }
  }

  /// Get connection type (WiFi, Mobile, etc)
  static Future<String> getConnectionType() async {
    try {
      final String? connType = await _channel.invokeMethod('getConnectionType');
      return connType?.toLowerCase() ?? 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }

  /// Returns true when Android battery optimizations are disabled for the app.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final bool? value = await _channel.invokeMethod('isIgnoringBatteryOptimizations');
      return value ?? false;
    } catch (e) {
      return true;
    }
  }

  /// Opens Android settings screen to allow unrestricted background execution.
  static Future<bool> openBatteryOptimizationSettings() async {
    try {
      final bool? opened = await _channel.invokeMethod('openBatteryOptimizationSettings');
      return opened ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Returns stable hardware identifier for server-side account binding.
  static Future<String> getHardwareId() async {
    try {
      final String? hwid = await _channel.invokeMethod('getHardwareId');
      if (hwid != null && hwid.trim().isNotEmpty) {
        return hwid.trim();
      }
      return 'unknown-hwid';
    } catch (e) {
      return 'unknown-hwid';
    }
  }
}
