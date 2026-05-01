import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/auth_cubit.dart';
import '../features/home/vpn_cubit.dart';
import '../features/settings/settings_cubit.dart';
import '../features/stats/stats_cubit.dart';
import 'router.dart';

class ByteAwayApp extends StatelessWidget {
  final AuthCubit authCubit;

  const ByteAwayApp({super.key, required this.authCubit});

  @override
  Widget build(BuildContext context) {
    final router = createRouter(authCubit);
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: authCubit),
        BlocProvider(create: (_) => VpnCubit()),
        BlocProvider(create: (_) => StatsCubit()),
        BlocProvider(create: (_) => SettingsCubit()),
      ],
      child: MaterialApp.router(
        title: 'ByteAway',
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    );
  }
}
