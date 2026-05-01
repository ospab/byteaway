import 'package:flutter/services.dart';
import '../constants.dart';

class DeviceInfoService {
  static const MethodChannel _channel = MethodChannel(AppConstants.deviceChannel);

  static Future<String> getDeviceId() async {
    final id = await _channel.invokeMethod<String>('getDeviceId');
    return (id ?? '').trim();
  }

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final info = await _channel.invokeMethod<Map>('getDeviceInfo');
    return Map<String, dynamic>.from(info ?? {});
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    final value = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return value ?? false;
  }

  static Future<void> openBatteryOptimizationSettings() async {
    await _channel.invokeMethod('openBatteryOptimizationSettings');
  }
}
