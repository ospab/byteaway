import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/di.dart';
import '../../core/constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/device_info_service.dart';
import '../../core/services/log_service.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(AuthState.initial());

  final ApiClient _api = sl<ApiClient>();

  Future<void> bootstrap() async {
    emit(state.copyWith(isLoading: true, error: null));
    final prefs = sl.get<SharedPreferences>();
    final stored = prefs.getString('auth_token');
    if (stored != null && stored.isNotEmpty) {
      _api.setToken(stored);
      final ok = await _probeAuth();
      if (ok) {
        emit(state.copyWith(isLoading: false, isAuthenticated: true));
        return;
      }
    }

    await registerNode();
  }

  Future<void> registerNode() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final deviceId = await DeviceInfoService.getDeviceId();
      if (deviceId.isEmpty) {
        throw StateError('Device ID not available');
      }

      final response = await _api.postJson(
        AppConstants.registerNodeEndpoint,
        data: {'device_id': deviceId},
      );

      final token = (response['token'] as String?)?.trim() ?? deviceId;
      _api.setToken(token);

      final prefs = sl.get<SharedPreferences>();
      await prefs.setString('auth_token', token);
      await prefs.setString('device_id', deviceId);

      emit(state.copyWith(isLoading: false, isAuthenticated: true));
    } catch (e) {
      await LogService.write('auth.registerNode error: $e');
      emit(state.copyWith(isLoading: false, isAuthenticated: false, error: e.toString()));
    }
  }

  Future<bool> _probeAuth() async {
    try {
      await _api.getJson('/balance');
      return true;
    } catch (_) {
      return false;
    }
  }
}
