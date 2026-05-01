import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_cubit.dart';
import '../features/auth/auth_screen.dart';
import '../features/home/home_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/split_tunnel_screen.dart';
import '../features/settings/log_screen.dart';
import '../core/theme/app_theme.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => navigationShell.goBranch(index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textSecondary,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.shield_rounded), label: 'Главная'),
            BottomNavigationBarItem(icon: Icon(Icons.analytics_rounded), label: 'Статистика'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Настройки'),
          ],
        ),
      ),
    );
  }
}

GoRouter createRouter(AuthCubit authCubit) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: GoRouterRefreshStream(authCubit.stream),
    redirect: (context, state) {
      final isAuthed = authCubit.state.isAuthenticated;
      final isLoading = authCubit.state.isLoading;
      final isAuthRoute = state.matchedLocation == '/auth';

      if (isLoading) {
        return isAuthRoute ? null : '/auth';
      }

      if (!isAuthed && !isAuthRoute) return '/auth';
      if (isAuthed && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
              GoRoute(
                path: '/settings/split-tunnel',
                builder: (context, state) => const SplitTunnelScreen(),
              ),
              GoRoute(
                path: '/settings/logs',
                builder: (context, state) => const LogScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
