import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../theme/app_theme.dart';
import '../widgets/status_card.dart';
import '../widgets/traffic_chart.dart';
import '../widgets/glass_scaffold.dart';
import 'statistics_cubit.dart';
import 'statistics_state.dart';

/// Statistics screen: traffic chart + summary cards with Glassmorphism.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      title: 'Статистика',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          onPressed: () => context.read<StatisticsCubit>().loadStats(),
        ),
        const SizedBox(width: 8),
      ],
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
                  const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: const TextStyle(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<StatisticsCubit>().loadStats(),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }

          if (state is StatisticsLoaded) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 100, 20, 80),
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
                          value: '${state.totalConsumedGb.toStringAsFixed(2)} GB',
                          icon: Icons.cloud_download_outlined,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  StatusCard(
                    title: 'Заработано',
                    value: '\$${state.totalEarnedUsd.toStringAsFixed(2)}',
                    subtitle: 'За последние 30 дней',
                    icon: Icons.attach_money_rounded,
                    iconColor: AppTheme.success,
                  ),

                  const SizedBox(height: 32),

                  // ── Chart ────────────────────────────
                  _buildSectionHeader('ТРАФИК ПО ДНЯМ'),
                  const SizedBox(height: 16),

                  _buildGlassContainer(
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LegendItem(color: AppTheme.primary, label: 'Отдано'),
                            SizedBox(width: 20),
                            _LegendItem(color: AppTheme.accent, label: 'Потреблено'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TrafficChart(records: state.records),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Daily List ───────────────────────
                  _buildSectionHeader('ДЕТАЛИЗАЦИЯ'),
                  const SizedBox(height: 12),

                  ...state.records.reversed.map((record) => _buildDailyRow(record)),
                ],
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppTheme.primary,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  Widget _buildDailyRow(dynamic record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Text(
            '${record.date.day.toString().padLeft(2, '0')}.${record.date.month.toString().padLeft(2, '0')}',
            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const Spacer(),
          _DataInfo(icon: Icons.cloud_upload_outlined, value: '${record.sharedGb.toStringAsFixed(2)}G', color: AppTheme.primary),
          const SizedBox(width: 12),
          _DataInfo(icon: Icons.cloud_download_outlined, value: '${record.consumedGb.toStringAsFixed(2)}G', color: AppTheme.accent),
          const SizedBox(width: 12),
          Text(
            '\$${record.earnedUsd.toStringAsFixed(2)}',
            style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _DataInfo extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _DataInfo({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color.withOpacity(0.7)),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ],
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, letterSpacing: 0.5)),
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
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }
}
