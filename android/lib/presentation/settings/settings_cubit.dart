import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/datasources/auth_local_ds.dart';
import 'settings_state.dart';

/// Cubit managing sharing settings: speed limit, WiFi-only, mobile data.
class SettingsCubit extends Cubit<SettingsState> {
  final AuthLocalDataSource _localDs;

  SettingsCubit(this._localDs) : super(const SettingsState()) {
    _loadSettings();
  }

  void _loadSettings() {
    emit(SettingsState(
      speedLimitMbps: _localDs.getSpeedLimit(),
      wifiOnly: true, // Always locked on
      allowMobileData: _localDs.getAllowMobile(),
    ));
  }

  /// Update speed limit (1–100 Mbps).
  Future<void> setSpeedLimit(int mbps) async {
    final clamped = mbps.clamp(1, 100);
    await _localDs.setSpeedLimit(clamped);
    emit(state.copyWith(speedLimitMbps: clamped));
  }

  /// Toggle mobile data sharing (off by default).
  Future<void> toggleMobileData(bool allow) async {
    await _localDs.setAllowMobile(allow);
    emit(state.copyWith(allowMobileData: allow));
  }
}
