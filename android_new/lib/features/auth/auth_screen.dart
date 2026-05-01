import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import 'auth_cubit.dart';
import 'auth_state.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.ambientGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ByteAway',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Подключайтесь к сети без ручных настроек — с поддержкой Reality и OSTP.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 32),
                    BlocBuilder<AuthCubit, AuthState>(
                      builder: (context, state) {
                        return PrimaryButton(
                          label: state.isLoading ? 'Подключаем...' : 'Продолжить',
                          isLoading: state.isLoading,
                          onPressed: state.isLoading
                              ? null
                              : () => context.read<AuthCubit>().registerNode(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    BlocBuilder<AuthCubit, AuthState>(
                      builder: (context, state) {
                        if (state.error == null || state.error!.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          state.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.error),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
