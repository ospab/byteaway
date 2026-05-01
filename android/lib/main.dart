import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app/di.dart';
import 'app/router.dart';
import 'presentation/auth/auth_cubit.dart';
import 'presentation/home/home_cubit.dart';
import 'presentation/settings/settings_cubit.dart';
import 'presentation/statistics/statistics_cubit.dart';
import 'presentation/theme/app_theme.dart';
import 'core/constants.dart';
import 'core/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logger with file persistence
  await AppLogger.init();

  // Optimize rendering performance
  if (!AppConstants.isDevelopment) {
    // Disable debug banners and optimize for release
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Preload critical resources
      _preloadCriticalResources();
    });
  }

  // Redirect debugPrint to AppLogger
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      AppLogger.log(message);
      debugPrintThrottled(message, wrapWidth: wrapWidth);
    }
  };

  // Lock app to portrait orientation.
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

  // In release builds, route debugPrint through AppLogger only (no console spam).
  // In debug builds, keep original behavior for full diagnostics.
  if (!AppConstants.isDevelopment) {
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        AppLogger.log(message);
      }
    };
  }

  // Check auth state before routing
  final authCubit = sl<AuthCubit>();
  await authCubit.checkAuth();

  runApp(const ByteAwayApp());
}

/// Preload critical resources for better performance
void _preloadCriticalResources() {
  // Precache fonts and images if needed
  // This can be expanded based on app requirements
  AppLogger.log('Critical resources preloaded');
}

class ByteAwayApp extends StatelessWidget {
  const ByteAwayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<AuthCubit>()),
        BlocProvider(create: (_) => sl<HomeCubit>()),
        BlocProvider(create: (_) => sl<StatisticsCubit>()),
        BlocProvider(create: (_) => sl<SettingsCubit>()),
      ],
      child: BlocListener<AuthCubit, dynamic>(
        listener: (context, state) {
          appRouter.refresh();
        },
        child: MaterialApp.router(
          title: 'ByteAway',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final clampedScale = media.textScaler.scale(1.0).clamp(0.9, 1.15);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(clampedScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
