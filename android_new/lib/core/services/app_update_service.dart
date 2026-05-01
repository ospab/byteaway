import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../models/update_info.dart';

class AppUpdateService {
  static const MethodChannel _channel = MethodChannel(AppConstants.updaterChannel);
  static const _cachedBuildKey = 'cached_update_build';
  static const _cachedPathKey = 'cached_update_path';

  static Future<AppUpdateInfo?> checkForUpdates() async {
    final manifest = await _fetchManifest();
    if (manifest == null) return null;

    final package = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(package.buildNumber) ?? 0;
    final remoteBuild = _parseInt(manifest['build_number']);
    final remoteVersion = (manifest['version']?.toString().trim() ?? '');
    final apkMeta = manifest['apk'] is Map ? manifest['apk'] as Map : null;

    final apkUrl = _normalizeApkUrl(
      (apkMeta?['url'] ?? manifest['apk_url'])?.toString().trim() ?? '',
    );
    final apkSha256 = (apkMeta?['sha256'] ?? manifest['apk_sha256'])?.toString().trim();
    final apkSizeBytes = _parseInt(apkMeta?['size_bytes'] ?? manifest['apk_size_bytes']);
    final changelog = (manifest['changelog']?.toString().trim() ?? '');
    final minSupportedBuild = _parseInt(manifest['min_supported_build']) ?? 1;

    if (remoteBuild == null || remoteVersion.isEmpty || apkUrl.isEmpty) {
      throw StateError('Некорректный манифест обновления');
    }

    if (remoteBuild <= currentBuild) return null;

    final mandatory = currentBuild < minSupportedBuild;

    return AppUpdateInfo(
      version: remoteVersion,
      buildNumber: remoteBuild,
      apkUrl: apkUrl,
      apkSha256: (apkSha256 != null && apkSha256.isNotEmpty) ? apkSha256 : null,
      apkSizeBytes: apkSizeBytes,
      changelog: changelog,
      mandatory: mandatory,
      minSupportedBuild: minSupportedBuild,
    );
  }

  static Future<bool> installPendingCachedUpdateIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedPath = prefs.getString(_cachedPathKey);
    if (cachedPath == null || cachedPath.isEmpty) return false;

    final file = File(cachedPath);
    if (!await file.exists()) {
      await prefs.remove(_cachedPathKey);
      await prefs.remove(_cachedBuildKey);
      return false;
    }

    final ok = await _installApk(file.path);
    return ok;
  }

  static Future<void> downloadAndInstall(
    AppUpdateInfo update, {
    required void Function(double) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/byteaway_${update.buildNumber}.apk');

    final dio = Dio();
    await dio.download(
      update.apkUrl,
      file.path,
      onReceiveProgress: (count, total) {
        if (total > 0) {
          onProgress(count / total);
        }
      },
      options: Options(responseType: ResponseType.bytes),
    );

    if (update.apkSha256 != null) {
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (digest.toLowerCase() != update.apkSha256!.toLowerCase()) {
        throw StateError('SHA256 не совпал, APK поврежден');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedPathKey, file.path);
    await prefs.setInt(_cachedBuildKey, update.buildNumber);

    final ok = await _installApk(file.path);
    if (!ok) {
      throw StateError('Не удалось запустить установку APK');
    }
  }

  static Future<bool> canInstallUnknownApps() async {
    final ok = await _channel.invokeMethod<bool>('canInstallUnknownApps');
    return ok ?? false;
  }

  static Future<void> openUnknownAppsSettings() async {
    await _channel.invokeMethod('openUnknownAppsSettings');
  }

  static Future<bool> _installApk(String path) async {
    final ok = await _channel.invokeMethod<bool>('installApk', {'filePath': path});
    return ok ?? false;
  }

  static Future<Map<String, dynamic>?> _fetchManifest() async {
    final resp = await Dio().get(
      AppConstants.updateManifestUrl,
      queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
      options: Options(responseType: ResponseType.plain),
    );

    final body = (resp.data ?? '').toString().trim();
    if (body.isEmpty) return null;
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String _normalizeApkUrl(String raw) {
    if (raw.startsWith('http')) return raw;
    if (raw.startsWith('/')) return '${AppConstants.baseUrl}$raw';
    return '${AppConstants.baseUrl}/$raw';
  }
}
