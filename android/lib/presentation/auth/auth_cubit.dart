import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/datasources/auth_local_ds.dart';
import '../../core/services/device_info_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/login_usecase.dart';
import 'auth_state.dart';

/// Manages authentication flow (token input → validation → persist).
class AuthCubit extends Cubit<AuthState> {
  final LoginUseCase _loginUseCase;
  final AuthRepository _authRepository;
  final AuthLocalDataSource _authLocalDs;

  AuthCubit(this._loginUseCase, this._authRepository, this._authLocalDs)
      : super(const AuthInitial());

  /// Check if already logged in on app startup.
  Future<void> checkAuth() async {
    final storedId = _authLocalDs.getDeviceId();
    if (storedId == null || !_isValidDeviceId(storedId)) {
      return;
    }

    try {
      final success = await _loginUseCase(storedId);
      if (success) {
        emit(const AuthSuccess());
      }
    } catch (_) {
      // Keep initial state; user can retry from login screen.
    }
  }

  /// Initialize anonymous session for B2C users.
  Future<void> startAnonymousSession() async {
    emit(const AuthLoading());

    try {
      final hardwareId = await DeviceInfoService.getHardwareId();
      final storedId = _authLocalDs.getDeviceId();
      String deviceId;

      if (_isValidDeviceId(hardwareId)) {
        deviceId = hardwareId;
        await _authLocalDs.saveDeviceId(deviceId);
      } else if (storedId != null && _isValidDeviceId(storedId)) {
        deviceId = storedId;
      } else {
        emit(const AuthFailureState('Не удалось получить стабильный HWID устройства. Перезапустите приложение и попробуйте снова.'));
        return;
      }
      
      final success = await _loginUseCase(deviceId);
      if (success) {
        emit(const AuthSuccess());
      } else {
        emit(const AuthFailureState('Не удалось инициализировать сессию. Попробуйте позже.'));
      }
    } catch (e) {
      emit(AuthFailureState('Ошибка подключения: ${e.toString()}'));
    }
  }

  /// Logout — clear stored token.
  Future<void> logout() async {
    await _authRepository.logout();
    emit(const AuthInitial());
  }

  bool _isValidDeviceId(String? id) {
    if (id == null) return false;
    final value = id.trim().toLowerCase();
    if (value.isEmpty) return false;
    if (value == 'unknown-hwid') return false;
    if (value == 'unknown-device') return false;
    return true;
  }
}
