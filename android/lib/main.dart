import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app/di.dart';
import 'app/router.dart';
import 'presentation/auth/auth_cubit.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // System UI style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize DI
  await initDependencies();

  // Check auth state before routing
  final authCubit = sl<AuthCubit>();
  await authCubit.checkAuth();

  runApp(const ByteAwayApp());
}

class ByteAwayApp extends StatelessWidget {
  const ByteAwayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: sl<AuthCubit>(),
      child: BlocListener<AuthCubit, dynamic>(
        listener: (context, state) {
          // Re-evaluate routes on auth state change
          appRouter.refresh();
        },
        child: MaterialApp.router(
          title: 'ByteAway',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
