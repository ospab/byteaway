import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/login_usecase.dart';
import 'auth_state.dart';

/// Manages authentication flow (token input → validation → persist).
class AuthCubit extends Cubit<AuthState> {
  final LoginUseCase _loginUseCase;
  final AuthRepository _authRepository;

  AuthCubit(this._loginUseCase, this._authRepository) : super(const AuthInitial());

  /// Check if already logged in on app startup.
  Future<void> checkAuth() async {
    final isLoggedIn = await _authRepository.isLoggedIn();
    if (isLoggedIn) {
      emit(const AuthSuccess());
    }
  }

  /// Initialize anonymous session for B2C users.
  Future<void> startAnonymousSession() async {
    emit(const AuthLoading());

    try {
      // For B2C, we generate a random UUID as the device token to authenticate with the network.
      // E.g. using a unique device identifier or generated UUID. We'll simulate a UUID here
      // since we aren't adding the 'uuid' package check if it's imported yet, but we saw it in pubspec.yaml.
      // Wait, let's just create a strong timestamp-based mock UUID or use the uuid package if we import it.
      // Better yet, just pass a dummy "b2c-device-token" for now until the backend is fully connected.
      final dummyDeviceToken = 'b2c-node-' + DateTime.now().millisecondsSinceEpoch.toString();
      
      final success = await _loginUseCase(dummyDeviceToken);
      if (success) {
        emit(const AuthSuccess());
      } else {
        emit(const AuthFailureState('Не удалось инициализировать соединение. Попробуйте позже.'));
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
}
