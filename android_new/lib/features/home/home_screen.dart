import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants.dart';
import '../../core/models/vpn_status.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../stats/stats_cubit.dart';
import '../stats/stats_state.dart';
import 'vpn_cubit.dart';
import 'vpn_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    context.read<StatsCubit>().loadStats();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ByteAway',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          _buildStatusCard(context),
          const SizedBox(height: 16),
          _buildNodeToggle(),
          const SizedBox(height: 16),
          _buildTrafficSummary(),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return BlocBuilder<VpnCubit, VpnState>(
      builder: (context, state) {
        final status = state.status.state;
        final isConnected = status == VpnConnectionState.connected;
        final isConnecting = status == VpnConnectionState.connecting;
        final label = isConnected
            ? 'VPN активен'
            : isConnecting
                ? 'Подключение...'
                : 'VPN выключен';
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isConnected ? AppTheme.success : AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    _formatUptime(state.status.uptime),
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: isConnected ? 'Отключить' : 'Подключиться',
                isLoading: isConnecting,
                onPressed: isConnecting
                    ? null
                    : () {
                        final cubit = context.read<VpnCubit>();
                        isConnected ? cubit.disconnect() : cubit.connect();
                      },
              ),
              if (state.message != null && state.message!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(state.message!, style: const TextStyle(color: AppTheme.error)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNodeToggle() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Узел сети', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Скоро будет доступно', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(value: false, onChanged: null),
        ],
      ),
    );
  }

  Widget _buildTrafficSummary() {
    return BlocBuilder<StatsCubit, StatsState>(
      builder: (context, state) {
        final today = DateTime.now();
        final record = state.records.where((r) => _isSameDay(r.date, today)).toList();
        final consumedBytes = record.isNotEmpty ? record.last.bytesConsumed : 0;
        final consumedGb = consumedBytes / 1073741824.0;
        final limitGb = AppConstants.freeDailyLimitBytes / 1073741824.0;
        final progress = (consumedBytes / AppConstants.freeDailyLimitBytes).clamp(0.0, 1.0);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Лимит сегодня', style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('${consumedGb.toStringAsFixed(2)} GB', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('/ ${limitGb.toStringAsFixed(0)} GB', style: const TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white.withOpacity(0.08),
                  valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatUptime(Duration uptime) {
    if (uptime == Duration.zero) return '00:00';
    final h = uptime.inHours;
    final m = uptime.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = uptime.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
