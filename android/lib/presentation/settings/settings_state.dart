import 'package:equatable/equatable.dart';

/// Settings state.
class SettingsState extends Equatable {
  final int speedLimitMbps;
  final bool wifiOnly;         // Locked ON
  final bool allowMobileData;  // OFF by default

  const SettingsState({
    this.speedLimitMbps = 50,
    this.wifiOnly = true,
    this.allowMobileData = false,
  });

  SettingsState copyWith({
    int? speedLimitMbps,
    bool? wifiOnly,
    bool? allowMobileData,
  }) {
    return SettingsState(
      speedLimitMbps: speedLimitMbps ?? this.speedLimitMbps,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      allowMobileData: allowMobileData ?? this.allowMobileData,
    );
  }

  @override
  List<Object?> get props => [speedLimitMbps, wifiOnly, allowMobileData];
}
