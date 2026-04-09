import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

class AppUpdateInfo {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String? apkSha256;
  final int? apkSizeBytes;
  final String changelog;
  final bool mandatory;
  final int minSupportedBuild;

  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    this.apkSha256,
    this.apkSizeBytes,
    required this.changelog,
    required this.mandatory,
    required this.minSupportedBuild,
  });
}

class AppUpdateCheckResult {
  final String currentVersion;
  final int currentBuild;
  final String remoteVersion;
  final int remoteBuild;
  final AppUpdateInfo? update;

  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.currentBuild,
    required this.remoteVersion,
    required this.remoteBuild,
    required this.update,
  });

  bool get isUpdateAvailable => update != null;
}

class UnknownSourcesPermissionException implements Exception {
  final String message;

  const UnknownSourcesPermissionException(this.message);

  @override
  String toString() => message;
}

class AppUpdateService {
  static const MethodChannel _channel =
      MethodChannel(AppConstants.updaterChannel);

  static Future<String> getDisplayVersion() async {
    try {
      final manifest = await _fetchManifest();
      final remoteVersion = (manifest?['version']?.toString().trim() ?? '');
      if (remoteVersion.isNotEmpty) {
        return remoteVersion;
      }
    } catch (_) {
      // Fallback to local version if server version is temporarily unavailable.
    }

    final package = await PackageInfo.fromPlatform();
    return package.version;
  }

  static Future<AppUpdateInfo?> checkForUpdates() async {
    final result = await checkForUpdatesDetailed();
    return result.update;
  }

  static Future<AppUpdateCheckResult> checkForUpdatesDetailed() async {
    final package = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(package.buildNumber) ?? 0;

    // Keep update cache tidy: remove stale/broken artifacts before checking server.
    await _cleanupCachedUpdates(currentBuild);

    final manifest = await _fetchManifest();
    if (manifest == null) {
      throw StateError('Некорректный формат манифеста обновления');
    }

    final remoteBuild = _parseInt(manifest['build_number']);
    final remoteVersion = (manifest['version']?.toString().trim() ?? '');
    final apkMeta = _asMap(manifest['apk']);
    final apkUrl = _normalizeApkUrl(
      apkMeta?['url']?.toString().trim() ??
          manifest['apk_url']?.toString().trim() ??
          '',
    );
    final apkSha256 =
        (apkMeta?['sha256'] ?? manifest['apk_sha256'])?.toString().trim();
    final apkSizeBytes =
        _parseInt(apkMeta?['size_bytes'] ?? manifest['apk_size_bytes']);
    final changelog = (manifest['changelog']?.toString().trim() ?? '');
    final minSupportedBuild = _parseInt(manifest['min_supported_build']) ?? 1;
    final mandatory = manifest['mandatory'] == true ||
        (remoteBuild != null && currentBuild < minSupportedBuild);

    _validateManifestSecurity(
      manifest: manifest,
      apkUrl: apkUrl,
      currentBuild: currentBuild,
      remoteBuild: remoteBuild,
      apkSha256: apkSha256,
      apkSizeBytes: apkSizeBytes,
    );

    if (remoteBuild == null || remoteVersion.isEmpty || apkUrl.isEmpty) {
      throw StateError('Манифест обновления неполный или поврежден');
    }

    final hasNewBuild = remoteBuild > currentBuild;

    AppUpdateInfo? update;
    if (hasNewBuild) {
      update = AppUpdateInfo(
        version: remoteVersion,
        buildNumber: remoteBuild,
        apkUrl: apkUrl,
        apkSha256: (apkSha256?.isNotEmpty ?? false) ? apkSha256 : null,
        apkSizeBytes: apkSizeBytes,
        changelog: changelog,
        mandatory: mandatory,
        minSupportedBuild: minSupportedBuild,
      );
    }

    return AppUpdateCheckResult(
      currentVersion: package.version,
      currentBuild: currentBuild,
      remoteVersion: remoteVersion,
      remoteBuild: remoteBuild,
      update: update,
    );
  }

  static Future<Map<String, dynamic>?> _fetchManifest() async {
    const url = AppConstants.updateManifestUrl;
    final token = await _readAuthToken();

    if (token == null || token.isEmpty) {
      throw StateError('Для проверки обновлений требуется авторизация в приложении.');
    }

    late final Response<String> response;
    try {
      response = await Dio().get<String>(
        url,
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Accept': 'application/json,text/plain,*/*',
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw StateError(_mapDioToUpdateError(e, context: 'manifest'));
    }

    final body = (response.data ?? '').trim();
    final contentType = (response.headers.value('content-type') ?? '').toLowerCase();

    if (body.isEmpty) {
      throw StateError('Пустой ответ манифеста обновления: $url');
    }

    final looksLikeHtml =
        contentType.contains('text/html') ||
        body.startsWith('<!doctype html') ||
        body.startsWith('<html');

    if (looksLikeHtml) {
      throw StateError(
        'Сервер вернул HTML вместо JSON по адресу $url. '
        'Проверьте деплой сайта и наличие файла /downloads/android.json на сервере.',
      );
    }

    try {
      return _parseManifest(body);
    } on FormatException {
      throw StateError(
        'Манифест по адресу $url не является валидным JSON.',
      );
    }
  }

  static String _mapDioToUpdateError(DioException e, {required String context}) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final bodyText = data == null ? '' : data.toString().trim();
    final scope = context == 'apk' ? 'загрузки APK' : 'проверки обновлений';

    if (status == 401) {
      return 'Сессия истекла для $scope. Войдите в аккаунт заново.';
    }
    if (status == 403) {
      return 'Доступ к обновлениям запрещен (403). Проверьте авторизацию и права аккаунта.';
    }
    if (status == 404) {
      return 'Сервис обновлений временно недоступен (404).';
    }
    if (status != null && status >= 500) {
      return 'Сервер обновлений временно недоступен ($status). Повторите попытку позже.';
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Превышено время ожидания при $scope. Проверьте интернет и попробуйте снова.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Не удалось подключиться к серверу при $scope. Проверьте сеть.';
    }

    if (bodyText.isNotEmpty) {
      return 'Ошибка $scope: $bodyText';
    }

    return 'Не удалось выполнить операцию $scope. Попробуйте позже.';
  }

  static Map<String, dynamic>? _parseManifest(dynamic raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }

    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static String _normalizeApkUrl(String rawUrl) {
    if (rawUrl.isEmpty) return '';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return '';

    if (uri.hasScheme) {
      return rawUrl;
    }

    final base = Uri.parse(AppConstants.updateManifestUrl);
    return base.resolveUri(uri).toString();
  }

  static Future<int?> latestCachedBuildAboveCurrent() async {
    final package = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(package.buildNumber) ?? 0;
    final supportDir = await getApplicationSupportDirectory();
    final updatesDir = Directory('${supportDir.path}/updates');
    if (!await updatesDir.exists()) {
      return null;
    }

    final re = RegExp(r'^byteaway_update_(\d+)\.apk$', caseSensitive: false);
    int? candidate;

    await for (final entity in updatesDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : '';
      final m = re.firstMatch(name);
      if (m == null) continue;
      final build = int.tryParse(m.group(1) ?? '');
      if (build == null) continue;
      if (build <= currentBuild) continue;
      final currentBest = candidate ?? -1;
      if (build > currentBest) {
        candidate = build;
      }
    }

    return candidate;
  }

  static Future<bool> installPendingCachedUpdateIfAny() async {
    final build = await latestCachedBuildAboveCurrent();
    if (build == null) return false;
    await installCachedUpdateApk(build);
    return true;
  }

  static Future<void> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final canInstall =
        await _channel.invokeMethod<bool>('canInstallUnknownApps') ?? true;
    if (!canInstall) {
      throw const UnknownSourcesPermissionException(
        'Установка из неизвестных источников запрещена для ByteAway.',
      );
    }

    final file = await _cachedApkFile(update.buildNumber);
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) {
      throw StateError('Для загрузки обновления требуется авторизация в приложении.');
    }

    if (!await file.exists()) {
      final dio = Dio();
      try {
        await dio.download(
          update.apkUrl,
          file.path,
          deleteOnError: true,
          options: Options(
            receiveTimeout: const Duration(minutes: 10),
            headers: {
              'Authorization': 'Bearer $token',
            },
          ),
          onReceiveProgress: (count, total) {
            if (total <= 0) return;
            onProgress?.call(count / total);
          },
        );
      } on DioException catch (e) {
        throw StateError(_mapDioToUpdateError(e, context: 'apk'));
      }
    } else {
      onProgress?.call(1.0);
    }

    if (!await file.exists()) {
      throw StateError('APK file not found after download');
    }

    await _verifyDownloadedApk(file, update);
    await _writeCachedApkMeta(file, update);

    final ok = await _channel.invokeMethod<bool>('installApk', {'filePath': file.path}) ?? false;
    if (!ok) {
      throw StateError('Не удалось запустить установку APK');
    }
  }

  static Future<bool> hasCachedUpdateApk(int buildNumber) async {
    final file = await _cachedApkFile(buildNumber);
    return file.exists();
  }

  static Future<void> installCachedUpdateApk(int buildNumber) async {
    final canInstall =
        await _channel.invokeMethod<bool>('canInstallUnknownApps') ?? true;
    if (!canInstall) {
      throw const UnknownSourcesPermissionException(
        'Установка из неизвестных источников запрещена для ByteAway.',
      );
    }

    final file = await _cachedApkFile(buildNumber);
    if (!await file.exists()) {
      throw StateError('Скачанный APK не найден в кеше.');
    }

    await _verifyCachedApkIntegrity(file, buildNumber);

    final ok = await _channel.invokeMethod<bool>(
          'installApk',
          {'filePath': file.path},
        ) ??
        false;
    if (!ok) {
      throw StateError('Не удалось запустить установку APK из кеша');
    }
  }

  static Future<File> _cachedApkFile(int buildNumber) async {
    final supportDir = await getApplicationSupportDirectory();
    final updatesDir = Directory('${supportDir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    return File('${updatesDir.path}/byteaway_update_$buildNumber.apk');
  }

  static Future<File> _cachedApkMetaFile(int buildNumber) async {
    final supportDir = await getApplicationSupportDirectory();
    final updatesDir = Directory('${supportDir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    return File('${updatesDir.path}/byteaway_update_$buildNumber.meta.json');
  }

  static Future<void> _cleanupCachedUpdates(int currentBuild) async {
    final supportDir = await getApplicationSupportDirectory();
    final updatesDir = Directory('${supportDir.path}/updates');
    if (!await updatesDir.exists()) {
      return;
    }

    final apkRe = RegExp(r'^byteaway_update_(\d+)\.apk$', caseSensitive: false);
    final metaRe = RegExp(r'^byteaway_update_(\d+)\.meta\.json$', caseSensitive: false);

    final apkByBuild = <int, File>{};
    final metaByBuild = <int, File>{};

    await for (final entity in updatesDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : '';

      final apkMatch = apkRe.firstMatch(name);
      if (apkMatch != null) {
        final build = int.tryParse(apkMatch.group(1) ?? '');
        if (build != null) {
          apkByBuild[build] = entity;
        }
        continue;
      }

      final metaMatch = metaRe.firstMatch(name);
      if (metaMatch != null) {
        final build = int.tryParse(metaMatch.group(1) ?? '');
        if (build != null) {
          metaByBuild[build] = entity;
        }
      }
    }

    final allBuilds = <int>{...apkByBuild.keys, ...metaByBuild.keys};
    if (allBuilds.isEmpty) {
      return;
    }

    int? newestFutureBuild;
    for (final build in allBuilds) {
      if (build > currentBuild) {
        if (newestFutureBuild == null || build > newestFutureBuild) {
          newestFutureBuild = build;
        }
      }
    }

    for (final build in allBuilds) {
      final apk = apkByBuild[build];
      final meta = metaByBuild[build];

      final outdated = build <= currentBuild;
      final orphaned = apk == null || meta == null;
      final oldFutureDuplicate = newestFutureBuild != null && build > currentBuild && build != newestFutureBuild;

      if (!(outdated || orphaned || oldFutureDuplicate)) {
        continue;
      }

      if (apk != null) {
        await _safeDelete(apk);
      }
      if (meta != null) {
        await _safeDelete(meta);
      }
    }
  }

  static Future<void> openUnknownAppsSettings() async {
    await _channel.invokeMethod('openUnknownAppsSettings');
  }

  static void _validateManifestSecurity({
    required Map<String, dynamic> manifest,
    required String apkUrl,
    required int currentBuild,
    required int? remoteBuild,
    required String? apkSha256,
    required int? apkSizeBytes,
  }) {
    if (apkUrl.isEmpty) {
      throw StateError('В манифесте отсутствует APK URL');
    }

    final apkUri = Uri.tryParse(apkUrl);
    if (apkUri == null || !apkUri.hasScheme || !apkUri.hasAuthority) {
      throw StateError('Некорректный URL APK в манифесте');
    }

    final security = _asMap(manifest['security']);
    final requiresHttps = security?['requires_https'] == true;
    if (requiresHttps && apkUri.scheme.toLowerCase() != 'https') {
      throw StateError('Манифест требует HTTPS для загрузки APK');
    }

    final allowedHosts = _toStringList(security?['allowed_hosts']);
    if (allowedHosts.isNotEmpty && !allowedHosts.contains(apkUri.host)) {
      throw StateError('Хост APK не входит в список разрешенных манифестом');
    }

    final expiresAtRaw =
        security?['expires_at']?.toString().trim() ??
        manifest['expires_at']?.toString().trim();
    if (expiresAtRaw != null && expiresAtRaw.isNotEmpty) {
      final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
      if (expiresAt == null) {
        throw StateError('Некорректное значение expires_at в манифесте');
      }
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        throw StateError('Срок действия манифеста обновления истек');
      }
    }

    final antiRollback = security?['anti_rollback'] == true;
    // Equal build means "already on this version" and must not be treated as rollback.
    if (antiRollback && remoteBuild != null && remoteBuild < currentBuild) {
      throw StateError('Обнаружена попытка rollback обновления');
    }

    if (apkSha256 != null && apkSha256.isNotEmpty) {
      final normalized = apkSha256.toLowerCase();
      final re = RegExp(r'^[a-f0-9]{64}$');
      if (!re.hasMatch(normalized)) {
        throw StateError('Некорректный SHA-256 в манифесте обновления');
      }
    }

    if (apkSizeBytes != null && apkSizeBytes <= 0) {
      throw StateError('Некорректный размер APK в манифесте');
    }
  }

  static Future<void> _verifyDownloadedApk(File file, AppUpdateInfo update) async {
    if (update.apkSizeBytes != null) {
      final realSize = await file.length();
      if (realSize != update.apkSizeBytes) {
        throw StateError(
          'Размер APK не совпадает с манифестом: expected=${update.apkSizeBytes}, actual=$realSize',
        );
      }
    }

    final expectedHash = update.apkSha256?.toLowerCase();
    if (expectedHash != null && expectedHash.isNotEmpty) {
      final digest = await _sha256File(file);
      if (digest != expectedHash) {
        throw StateError('SHA-256 APK не совпадает с манифестом');
      }
    }
  }

  static Future<String> _sha256File(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString().toLowerCase();
  }

  static Future<void> _writeCachedApkMeta(File file, AppUpdateInfo update) async {
    final hash = await _sha256File(file);
    final size = await file.length();
    final metaFile = await _cachedApkMetaFile(update.buildNumber);

    final payload = {
      'build_number': update.buildNumber,
      'apk_sha256': hash,
      'apk_size_bytes': size,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    };

    await metaFile.writeAsString(jsonEncode(payload), flush: true);
  }

  static Future<void> _verifyCachedApkIntegrity(File file, int buildNumber) async {
    // 1) Strong path: verify against current remote manifest when build matches.
    try {
      final detailed = await checkForUpdatesDetailed();
      final update = detailed.update;
      if (update != null && update.buildNumber == buildNumber) {
        await _verifyDownloadedApk(file, update);
        return;
      }
    } catch (_) {
      // Fallback to local sidecar verification below.
    }

    // 2) Fallback path: verify against sidecar metadata persisted after a successful full download.
    final metaFile = await _cachedApkMetaFile(buildNumber);
    if (!await metaFile.exists()) {
      await _safeDelete(file);
      throw StateError(
        'Кеш обновления не прошел проверку целостности (метаданные отсутствуют). '
        'Скачайте обновление заново.',
      );
    }

    final metaRaw = await metaFile.readAsString();
    final decoded = jsonDecode(metaRaw);
    if (decoded is! Map<String, dynamic>) {
      await _safeDelete(file);
      await _safeDelete(metaFile);
      throw StateError(
        'Кеш обновления не прошел проверку целостности (поврежденные метаданные). '
        'Скачайте обновление заново.',
      );
    }

    final expectedHash = (decoded['apk_sha256']?.toString().trim() ?? '').toLowerCase();
    final expectedSize = _parseInt(decoded['apk_size_bytes']);

    if (expectedHash.isEmpty || expectedSize == null || expectedSize <= 0) {
      await _safeDelete(file);
      await _safeDelete(metaFile);
      throw StateError(
        'Кеш обновления не прошел проверку целостности (некорректные метаданные). '
        'Скачайте обновление заново.',
      );
    }

    final actualSize = await file.length();
    if (actualSize != expectedSize) {
      await _safeDelete(file);
      await _safeDelete(metaFile);
      throw StateError(
        'Кеш обновления поврежден: размер файла не совпадает. '
        'Скачайте обновление заново.',
      );
    }

    final actualHash = await _sha256File(file);
    if (actualHash != expectedHash) {
      await _safeDelete(file);
      await _safeDelete(metaFile);
      throw StateError(
        'Кеш обновления поврежден: контрольная сумма не совпадает. '
        'Скачайте обновление заново.',
      );
    }
  }

  static Future<void> _safeDelete(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) {
        await entity.delete();
      }
    } catch (_) {
      // Best effort cleanup: ignore deletion failures.
    }
  }

  static Future<String?> _readAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.tokenKey)?.trim();
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }
}
