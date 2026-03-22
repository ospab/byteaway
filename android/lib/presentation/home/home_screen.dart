import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/entities/node_status.dart';
import '../theme/app_theme.dart';
import '../widgets/status_card.dart';
import '../widgets/vpn_toggle_button.dart';
import 'home_cubit.dart';
import 'home_state.dart';

/// Main dashboard screen:
/// VPN toggle, node status, balance, shared traffic.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // ── Header ───────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppTheme.primaryGradient.createShader(bounds),
                            child: Text(
                              'ByteAway',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 28,
                                    color: Colors.white,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: state.vpnStatus.isActive
                                      ? AppTheme.success
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _vpnStateLabel(state.vpnStatus.state),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Balance chip
                      if (state.balance != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.primary.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined,
                                  size: 16, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                '\$${state.balance!.balanceUsd.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // ── VPN Toggle Button ────────────────
                  VpnToggleButton(
                    isConnected: state.vpnStatus.isActive,
                    isLoading: state.vpnStatus.state ==
                            VpnConnectionState.connecting ||
                        state.vpnStatus.state ==
                            VpnConnectionState.disconnecting,
                    onPressed: () =>
                        context.read<HomeCubit>().toggleVpn(),
                  ),

                  const SizedBox(height: 12),

                  // VPN status label
                  Text(
                    state.vpnStatus.isActive ? 'Подключено' : 'Нажмите для подключения',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: state.vpnStatus.isActive
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                  ),

                  const SizedBox(height: 36),

                  // ── Status Cards ─────────────────────

                  // Balance / VPN Days
                  StatusCard(
                    title: 'Баланс VPN',
                    value: state.balance != null
                        ? '${state.balance!.vpnDaysRemaining.toStringAsFixed(0)} дней'
                        : '—',
                    subtitle: state.balance != null
                        ? '\$${state.balance!.balanceUsd.toStringAsFixed(2)}'
                        : null,
                    icon: Icons.calendar_today_rounded,
                    iconColor: AppTheme.primary,
                    trailing: state.isBalanceLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary,
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh_rounded,
                                color: AppTheme.textSecondary, size: 20),
                            onPressed: () =>
                                context.read<HomeCubit>().fetchBalance(),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // Node Status
                  StatusCard(
                    title: 'Статус узла',
                    value: _nodeStateLabel(state.nodeStatus.state),
                    subtitle: state.nodeStatus.isActive
                        ? '${state.nodeStatus.activeSessions} сессий • ${state.nodeStatus.currentSpeedMbps.toStringAsFixed(1)} Mbps'
                        : null,
                    icon: state.nodeStatus.isActive
                        ? Icons.cell_tower_rounded
                        : Icons.cell_tower_outlined,
                    iconColor: state.nodeStatus.isActive
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                    trailing: Switch(
                      value: state.nodeStatus.isActive,
                      onChanged: (_) =>
                          context.read<HomeCubit>().toggleNode(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Traffic Shared
                  StatusCard(
                    title: 'Отдано трафика',
                    value:
                        '${state.nodeStatus.totalSharedGb.toStringAsFixed(2)} GB',
                    subtitle: state.nodeStatus.isActive
                        ? 'Время работы: ${_formatDuration(state.nodeStatus.uptime)}'
                        : null,
                    icon: Icons.cloud_upload_outlined,
                    iconColor: AppTheme.accent,
                  ),

                  // Error display
                  if (state.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppTheme.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              state.error!,
                              style: const TextStyle(
                                  color: AppTheme.error, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _vpnStateLabel(VpnConnectionState s) {
    switch (s) {
      case VpnConnectionState.connected:
        return 'VPN активен';
      case VpnConnectionState.connecting:
        return 'Подключение...';
      case VpnConnectionState.disconnecting:
        return 'Отключение...';
      case VpnConnectionState.error:
        return 'Ошибка';
      case VpnConnectionState.disconnected:
        return 'Отключено';
    }
  }

  String _nodeStateLabel(NodeConnectionState s) {
    switch (s) {
      case NodeConnectionState.active:
        return 'Активен';
      case NodeConnectionState.connecting:
        return 'Подключение...';
      case NodeConnectionState.conditionWait:
        return 'Ожидание WiFi + зарядки';
      case NodeConnectionState.error:
        return 'Ошибка';
      case NodeConnectionState.inactive:
        return 'Неактивен';
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}ч ${m}м';
    return '${m}м';
  }
}
