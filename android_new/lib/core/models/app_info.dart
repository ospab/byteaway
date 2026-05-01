import 'dart:typed_data';

class AppInfo {
  final String packageName;
  final String label;
  final Uint8List icon;
  final bool isSystem;
  final int uid;

  const AppInfo({
    required this.packageName,
    required this.label,
    required this.icon,
    required this.isSystem,
    required this.uid,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    final rawIcon = map['icon'];
    Uint8List iconBytes = Uint8List(0);
    if (rawIcon is List) {
      try {
        iconBytes = Uint8List.fromList(List<int>.from(rawIcon));
      } catch (_) {}
    }
    return AppInfo(
      packageName: (map['package'] as String?) ?? '',
      label: (map['label'] as String?) ?? 'Unknown',
      icon: iconBytes,
      isSystem: (map['isSystem'] as bool?) ?? false,
      uid: (map['uid'] as int?) ?? 0,
    );
  }
}
