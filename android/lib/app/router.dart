import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'di.dart';
import '../presentation/auth/auth_cubit.dart';
import '../presentation/auth/auth_state.dart';
import '../presentation/auth/auth_screen.dart';
import '../presentation/home/home_cubit.dart';
import '../presentation/home/home_screen.dart';
import '../presentation/settings/settings_cubit.dart';
import '../presentation/settings/settings_screen.dart';
import '../presentation/statistics/statistics_cubit.dart';
import '../presentation/statistics/statistics_screen.dart';
import '../presentation/theme/app_theme.dart';

/// Main app shell with bottom navigation.
class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
            switch (index) {
              case 0:
                context.go('/');
                break;
              case 1:
                context.go('/statistics');
                break;
              case 2:
                context.go('/settings');
                break;
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Главная',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              activeIcon: Icon(Icons.bar_chart_rounded),
              label: 'Статистика',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Настройки',
            ),
          ],
        ),
      ),
    );
  }
}

/// GoRouter configuration with auth guard.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final authCubit = sl<AuthCubit>();
    final isLoggedIn = authCubit.state is AuthSuccess;
    final isLoginRoute = state.matchedLocation == '/login';

    if (!isLoggedIn && !isLoginRoute) {
      return '/login';
    }
    if (isLoggedIn && isLoginRoute) {
      return '/';
    }
    return null;
  },
  routes: [
    // Auth
    GoRoute(
      path: '/login',
      builder: (context, state) => BlocProvider.value(
        value: sl<AuthCubit>(),
        child: const AuthScreen(),
      ),
    ),

    // Main shell with bottom nav
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => BlocProvider(
            create: (_) => sl<HomeCubit>(),
            child: const HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/statistics',
          builder: (context, state) => BlocProvider(
            create: (_) => sl<StatisticsCubit>(),
            child: const StatisticsScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => BlocProvider(
            create: (_) => sl<SettingsCubit>(),
            child: const SettingsScreen(),
          ),
        ),
      ],
    ),
  ],
);
