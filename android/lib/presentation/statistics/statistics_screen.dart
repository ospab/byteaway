import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../theme/app_theme.dart';
import '../widgets/status_card.dart';
import '../widgets/traffic_chart.dart';
import 'statistics_cubit.dart';
import 'statistics_state.dart';

/// Statistics screen: traffic chart + summary cards.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<StatisticsCubit>().loadStats(),
          ),
        ],
      ),
      body: BlocBuilder<StatisticsCubit, StatisticsState>(
        builder: (context, state) {
          if (state is StatisticsLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (state is StatisticsError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppTheme.error, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: const TextStyle(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<StatisticsCubit>().loadStats(),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }

          if (state is StatisticsLoaded) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Summary Cards ────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          label: 'Отдано',
                          value: '${state.totalSharedGb.toStringAsFixed(2)} GB',
                          icon: Icons.cloud_upload_outlined,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryTile(
                          label: 'Потреблено',
                          value:
                              '${state.totalConsumedGb.toStringAsFixed(2)} GB',
                          icon: Icons.cloud_download_outlined,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  StatusCard(
                    title: 'Заработано',
                    value:
                        '\$${state.totalEarnedUsd.toStringAsFixed(2)}',
                    subtitle: 'За последние 30 дней',
                    icon: Icons.attach_money_rounded,
                    iconColor: AppTheme.success,
                  ),

                  const SizedBox(height: 28),

                  // ── Chart ────────────────────────────
                  Text(
                    'ТРАФИК ПО ДНЯМ',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: AppTheme.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      children: [
                        // Legend
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LegendItem(
                                color: AppTheme.primary, label: 'Отдано'),
                            const SizedBox(width: 20),
                            _LegendItem(
                                color: AppTheme.accent,
                                label: 'Потреблено'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TrafficChart(records: state.records),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Daily List ───────────────────────
                  Text(
                    'ДЕТАЛИЗАЦИЯ',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: AppTheme.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 12),

                  ...state.records.reversed.map((record) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.04)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${record.date.day.toString().padLeft(2, '0')}.${record.date.month.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.cloud_upload_outlined,
                              size: 14,
                              color: AppTheme.primary.withOpacity(0.7)),
                          const SizedBox(width: 4),
                          Text(
                            '${record.sharedGb.toStringAsFixed(2)}G',
                            style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13),
                          ),
                          const SizedBox(width: 14),
                          Icon(Icons.cloud_download_outlined,
                              size: 14,
                              color: AppTheme.accent.withOpacity(0.7)),
                          const SizedBox(width: 4),
                          Text(
                            '${record.consumedGb.toStringAsFixed(2)}G',
                            style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            '\$${record.earnedUsd.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
