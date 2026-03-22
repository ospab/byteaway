import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../theme/app_theme.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';

/// Settings screen: speed limit, WiFi-only (locked), mobile data toggle.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Section: Sharing ─────────────────
              _buildSectionHeader(context, 'Шаринг трафика'),
              const SizedBox(height: 12),

              // Speed Limit
              _buildCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.speed_rounded,
                                color: AppTheme.primary, size: 20),
                            SizedBox(width: 10),
                            Text('Лимит скорости',
                                style: TextStyle(
                                    color: AppTheme.textPrimary, fontSize: 15)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${state.speedLimitMbps} Mbps',
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.primary,
                        inactiveTrackColor: AppTheme.surfaceLight,
                        thumbColor: AppTheme.primary,
                        overlayColor: AppTheme.primary.withOpacity(0.1),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: state.speedLimitMbps.toDouble(),
                        min: 1,
                        max: 100,
                        divisions: 99,
                        label: '${state.speedLimitMbps} Mbps',
                        onChanged: (v) {
                          context
                              .read<SettingsCubit>()
                              .setSpeedLimit(v.round());
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1 Mbps',
                            style: TextStyle(
                                color: AppTheme.textSecondary.withOpacity(0.6),
                                fontSize: 11)),
                        Text('100 Mbps',
                            style: TextStyle(
                                color: AppTheme.textSecondary.withOpacity(0.6),
                                fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // WiFi Only — LOCKED
              _buildCard(
                context,
                child: Row(
                  children: [
                    const Icon(Icons.wifi_rounded,
                        color: AppTheme.success, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Только WiFi',
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 15)),
                          SizedBox(height: 2),
                          Text('Шаринг только при подключении к WiFi',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: state.wifiOnly,
                      onChanged: null, // Locked ON
                    ),
                    const Icon(Icons.lock_outline,
                        color: AppTheme.textSecondary, size: 16),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Allow Mobile Data
              _buildCard(
                context,
                child: Row(
                  children: [
                    const Icon(Icons.signal_cellular_alt_rounded,
                        color: AppTheme.warning, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Мобильный интернет',
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 15)),
                          SizedBox(height: 2),
                          Text(
                              'Разрешить шаринг через мобильные данные',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: state.allowMobileData,
                      onChanged: (v) {
                        context.read<SettingsCubit>().toggleMobileData(v);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Section: About ───────────────────
              _buildSectionHeader(context, 'О приложении'),
              const SizedBox(height: 12),

              _buildCard(
                context,
                child: const Column(
                  children: [
                    _InfoRow(label: 'Версия', value: '1.0.0'),
                    SizedBox(height: 8),
                    _InfoRow(label: 'Билд', value: '1'),
                    SizedBox(height: 8),
                    _InfoRow(label: 'Платформа', value: 'Android'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 12,
            letterSpacing: 1.2,
            color: AppTheme.textSecondary,
          ),
    );
  }

  Widget _buildCard(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        Text(value,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}
