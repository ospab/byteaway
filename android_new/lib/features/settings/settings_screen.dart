import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/app_update_service.dart';
import '../../widgets/app_scaffold.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTapCount = 0;

  @override
  void initState() {
    super.initState();
    context.read<SettingsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Настройки',
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _sectionTitle('VPN'),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: state.protocol,
                      decoration: _inputDecoration('Протокол'),
                      items: const [
                        DropdownMenuItem(value: 'vless', child: Text('VLESS + Reality')),
                        DropdownMenuItem(value: 'ostp', child: Text('OSTP')),
                      ],
                      onChanged: (value) {
                        if (value != null) context.read<SettingsCubit>().setProtocol(value);
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('MTU', style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${state.mtu}', style: const TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                    Slider(
                      min: 1280,
                      max: 1500,
                      divisions: 11,
                      value: state.mtu.toDouble(),
                      onChanged: (value) => context.read<SettingsCubit>().setMtu(value.toInt()),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: state.killSwitch,
                      onChanged: (value) => context.read<SettingsCubit>().setKillSwitch(value),
                      title: const Text('Kill Switch'),
                      subtitle: const Text('Блокировать трафик при разрыве VPN', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Функции'),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                      title: const Text('Split-Tunnel'),
                      subtitle: const Text('Исключить приложения из VPN', style: TextStyle(color: AppTheme.textSecondary)),
                      onTap: () => context.push('/settings/split-tunnel'),
                    ),
                    const Divider(color: Colors.white10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_rounded, color: AppTheme.primary),
                      title: const Text('Логи'),
                      subtitle: const Text('История диагностики', style: TextStyle(color: AppTheme.textSecondary)),
                      onTap: () => context.push('/settings/logs'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Обновления'),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.system_update_rounded, color: AppTheme.accent),
                      title: const Text('Проверить обновления'),
                      onTap: () => _checkUpdates(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('О приложении'),
              const SizedBox(height: 10),
              _card(
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.data?.version ?? '...';
                    final build = snapshot.data?.buildNumber ?? '...';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Версия'),
                      subtitle: Text('$version ($build)', style: const TextStyle(color: AppTheme.textSecondary)),
                      onTap: () => _handleVersionTap(context),
                    );
                  },
                ),
              ),
              if (state.hiddenUnlocked) ...[
                const SizedBox(height: 20),
                _sectionTitle('Скрытые настройки'),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    children: [
                      TextFormField(
                        initialValue: state.ostpHost,
                        decoration: _inputDecoration('OSTP host'),
                        onChanged: (v) => context.read<SettingsCubit>().setOstpHost(v.trim()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: state.ostpPort.toString(),
                        decoration: _inputDecoration('OSTP port'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => context.read<SettingsCubit>().setOstpPort(int.tryParse(v) ?? 8443),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: state.ostpLocalPort.toString(),
                        decoration: _inputDecoration('OSTP local port'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => context.read<SettingsCubit>().setOstpLocalPort(int.tryParse(v) ?? 1088),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: state.country,
                        decoration: _inputDecoration('Country code'),
                        onChanged: (v) => context.read<SettingsCubit>().setCountry(v.trim().toUpperCase()),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: state.connType,
                        decoration: _inputDecoration('Тип подключения'),
                        items: const [
                          DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi')),
                          DropdownMenuItem(value: 'mobile', child: Text('Mobile')),
                        ],
                        onChanged: (v) {
                          if (v != null) context.read<SettingsCubit>().setConnType(v);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _handleVersionTap(BuildContext context) {
    _versionTapCount += 1;
    if (_versionTapCount >= 5) {
      context.read<SettingsCubit>().unlockHidden();
    }
  }

  Future<void> _checkUpdates(BuildContext context) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(content: Text('Проверяем обновления...')));
    try {
      final update = await AppUpdateService.checkForUpdates();
      if (!context.mounted) return;
      if (update == null) {
        scaffold.showSnackBar(const SnackBar(content: Text('Обновлений нет')));
        return;
      }
      final shouldInstall = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                backgroundColor: AppTheme.surface,
                title: const Text('Доступно обновление'),
                content: Text('Версия ${update.version} (${update.buildNumber})\n\n${update.changelog}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Позже'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Обновить'),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (!shouldInstall) return;
      if (!context.mounted) return;

      final canInstall = await AppUpdateService.canInstallUnknownApps();
      if (!canInstall) {
        await AppUpdateService.openUnknownAppsSettings();
        return;
      }

      await AppUpdateService.downloadAndInstall(update, onProgress: (_) {});
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('Ошибка обновления: $e')));
    }
  }

  Widget _sectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(color: AppTheme.textSecondary, letterSpacing: 1.2, fontSize: 12),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.textSecondary),
      filled: true,
      fillColor: Colors.white.withOpacity(0.03),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}
