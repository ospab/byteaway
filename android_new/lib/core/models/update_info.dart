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
