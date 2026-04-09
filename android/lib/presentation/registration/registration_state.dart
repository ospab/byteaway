import 'package:equatable/equatable.dart';

class RegistrationState extends Equatable {
  final bool isLoading;
  final bool isSuccess;
  final String? error;

  const RegistrationState({
    this.isLoading = false,
    this.isSuccess = false,
    this.error,
  });

  RegistrationState copyWith({
    bool? isLoading,
    bool? isSuccess,
    String? error,
  }) {
    return RegistrationState(
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [isLoading, isSuccess, error];
}
