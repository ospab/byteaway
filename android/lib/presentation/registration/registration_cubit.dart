import 'package:flutter_bloc/flutter_bloc.dart';
import 'registration_state.dart';

class RegistrationCubit extends Cubit<RegistrationState> {
  RegistrationCubit() : super(const RegistrationState());

  Future<void> register(String email) async {
    emit(state.copyWith(isLoading: true, error: null));
    
    try {
      // TODO: Call API to create client with email
      // For now, just store email locally and navigate
      await Future.delayed(const Duration(seconds: 1));
      emit(state.copyWith(isLoading: false, isSuccess: true));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
