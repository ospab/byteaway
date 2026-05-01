import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import 'stats_cubit.dart';
import 'stats_state.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<StatsCubit>().loadStats();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Статистика',
      actions: [
        IconButton(
          onPressed: () => context.read<StatsCubit>().loadStats(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: BlocBuilder<StatsCubit, StatsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (state.error != null && state.error!.isNotEmpty) {
            return Center(
              child: Text(state.error!, style: const TextStyle(color: AppTheme.error)),
            );
          }
          if (state.records.isEmpty) {
            return const Center(child: Text('Пока нет статистики'));
          }

          final shared = state.records.map((r) => r.sharedGb).toList();
          final consumed = state.records.map((r) => r.consumedGb).toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Трафик по дням', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: List.generate(shared.length, (i) => FlSpot(i.toDouble(), shared[i])),
                        isCurved: true,
                        color: AppTheme.primary,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: List.generate(consumed.length, (i) => FlSpot(i.toDouble(), consumed[i])),
                        isCurved: true,
                        color: AppTheme.accent,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ...state.records.reversed.map((record) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${record.date.day.toString().padLeft(2, '0')}.${record.date.month.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      _MetricChip(label: '↑ ${record.sharedGb.toStringAsFixed(2)}G', color: AppTheme.primary),
                      const SizedBox(width: 8),
                      _MetricChip(label: '↓ ${record.consumedGb.toStringAsFixed(2)}G', color: AppTheme.accent),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetricChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
