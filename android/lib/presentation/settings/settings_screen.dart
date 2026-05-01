import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/services/app_update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_scaffold.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';

/// Settings screen: speed limit, WiFi-only, updates, and hidden controls.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTapCount = 0;
  bool _hiddenSettingsUnlocked = false;
  static const _vpnProtocols = ['vless', 'ostp'];
  static const _nodeTransports = ['quic', 'ws'];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 380;
    
    return GlassScaffold(
      title: 'Настройки',
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 100, 0, 20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: isNarrow ? 14 : 20),
                    child: Column(children: [
              // ── Section: Sharing ─────────────────
              _buildSectionHeader(context, 'Шаринг трафика'),
              const SizedBox(height: 12),

              _buildGlassCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.speed_rounded, color: AppTheme.primary, size: 20),
                            SizedBox(width: 10),
                            Text('Лимит скорости', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Text('${state.speedLimitMbps} Mbps', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Slider(
                      value: state.speedLimitMbps.toDouble(),
                      min: 1,
                      max: 100,
                      onChanged: (v) => context.read<SettingsCubit>().setSpeedLimit(v.round()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // WiFi-only toggle
              _buildGlassCard(
                context,
                child: Row(
                  children: [
                    const Icon(Icons.wifi_rounded, color: AppTheme.success, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Только WiFi', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('Раздача только по WiFi', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: state.wifiOnly,
                      onChanged: (v) => context.read<SettingsCubit>().toggleWifiOnly(v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Split-Tunnel navigation
              _buildGlassCard(
                context,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
                  title: const Text('Split-Tunnel', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Выбор приложений для обхода/прокси', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                  onTap: () => context.push('/split-tunnel'),
                ),
              ),



              const SizedBox(height: 32),

              // ── Section: About ───────────────────
              _buildSectionHeader(context, 'О приложении'),
              const SizedBox(height: 12),

              _buildGlassCard(
                context,
                child: Column(
                  children: [
                    FutureBuilder<String>(
                      future: _getBuildVersion(),
                      builder: (context, snapshot) {
                        final version = snapshot.data ?? '...';
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _onVersionTapped(context),
                          child: _InfoRow(label: 'Версия', value: version),
                        );
                      },
                    ),
                    const Divider(color: Colors.white10, height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.system_update_rounded, color: AppTheme.primary, size: 20),
                      title: const Text('Проверить обновления', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Скачивание и установка APK', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      onTap: () => _checkForUpdates(context),
                    ),
                  ],
                ),
              ),

              if (_hiddenSettingsUnlocked) ...[
                const SizedBox(height: 32),
                _buildSectionHeader(context, 'Скрытые настройки'),
                const SizedBox(height: 12),
                _buildGlassCard(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _nodeTransports.contains(state.nodeTransportMode)
                            ? state.nodeTransportMode
                            : _nodeTransports.first,
                        dropdownColor: const Color(0xFF171A21),
                        decoration: const InputDecoration(
                          labelText: 'Транспорт узла',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                        items: _nodeTransports
                            .map((mode) => DropdownMenuItem(
                                  value: mode,
                                  child: Text(mode.toUpperCase()),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          context.read<SettingsCubit>().setNodeTransportMode(value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _vpnProtocols.contains(state.vpnProtocol)
                            ? state.vpnProtocol
                            : _vpnProtocols.first,
                        dropdownColor: const Color(0xFF171A21),
                        decoration: const InputDecoration(
                          labelText: 'Протокол VPN',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                        items: _vpnProtocols
                            .map((protocol) => DropdownMenuItem(
                                  value: protocol,
                                  child: Text(protocol.toUpperCase()),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          context.read<SettingsCubit>().setVpnProtocol(value);
                        },
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.article_rounded, color: AppTheme.primary, size: 20),
                        title: const Text('Логи приложения', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Новые строки добавляются снизу', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        onTap: () => context.push('/logs'),
                      ),
                    ],
                  ),
                ),
              ],
                    ]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onVersionTapped(BuildContext context) {
    if (_hiddenSettingsUnlocked) return;
    _versionTapCount += 1;
    if (_versionTapCount >= 5) {
      setState(() {
        _hiddenSettingsUnlocked = true;
      });
      return;
    }
  }

  Future<String> _getBuildVersion() async {
    final package = await PackageInfo.fromPlatform();
    final build = package.buildNumber.trim();
    return '0.0.${build.isEmpty ? '0' : build}';
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildGlassCard(BuildContext context, {required Widget child}) {
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

  Future<void> _checkForUpdates(BuildContext context) async {
    try {
      final installedFromCache = await AppUpdateService.installPendingCachedUpdateIfAny();
      if (installedFromCache) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Найден сохраненный APK. Запускаем установку...')),
          );
        }
        return;
      }
    } catch (e) {
      if (e is UnknownSourcesPermissionException) {
        if (context.mounted) {
          await _showUnknownSourcesDialog(context);
        }
        return;
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Проверяем обновления...')),
    );

    try {
      final result = await AppUpdateService.checkForUpdatesDetailed();
      if (!result.isUpdateAvailable) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Обновлений нет. Локально: ${result.currentVersion}+${result.currentBuild}, '
                'сервер: ${result.remoteVersion}+${result.remoteBuild}',
              ),
            ),
          );
        }
        return;
      }

      final update = result.update!;

      if (!context.mounted) return;
      final shouldInstall = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                backgroundColor: const Color(0xFF171A21),
                title: const Text(
                  'Доступно обновление',
                  style: TextStyle(color: Colors.white),
                ),
                content: Text(
                  'Версия ${update.version} (build ${update.buildNumber})\n\n'
                  'Изменения:\n${_formatChangelog(update.changelog)}',
                  style: const TextStyle(color: Colors.white70),
                ),
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
      await _downloadAndInstallWithProgress(context, update);
    } catch (e) {
      if (!context.mounted) return;
      if (e is UnknownSourcesPermissionException) {
        await _showUnknownSourcesDialog(context);
        return;
      }
      final raw = e.toString();
      final cleaned = raw
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Exception: ', '')
          .trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обновления: $cleaned')),
      );
    }
  }

  Future<void> _showUnknownSourcesDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171A21),
          title: const Text(
            'Разрешите установку APK',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Android блокирует установку из неизвестных источников для ByteAway. '
            'Откройте настройки и включите разрешение "Устанавливать неизвестные приложения".',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Позже'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await AppUpdateService.openUnknownAppsSettings();
              },
              child: const Text('Открыть настройки'),
            ),
          ],
        );
      },
    );
  }

  String _formatChangelog(String changelog) {
    final text = changelog.trim();
    if (text.isEmpty) {
      return '• На сервере не указан changelog для этой версии.';
    }

    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return '• $text';
    }

    return lines
        .map((line) => line.startsWith('•') || line.startsWith('-') ? line : '• $line')
        .join('\n');
  }

  Future<void> _downloadAndInstallWithProgress(
    BuildContext context,
    AppUpdateInfo update,
  ) async {
    final progress = ValueNotifier<double>(0);
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171A21),
          title: const Text(
            'Скачивание обновления',
            style: TextStyle(color: Colors.white),
          ),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, value, _) {
              final percent = (value * 100).clamp(0, 100).toStringAsFixed(0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: value > 0 ? value : null,
                    minHeight: 8,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    value > 0
                        ? 'Загружено $percent%'
                        : 'Подготавливаем загрузку APK...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    try {
      await AppUpdateService.downloadAndInstall(
        update,
        onProgress: (value) {
          progress.value = value;
        },
      );

      if (context.mounted) {
        final rootNavigator = Navigator.of(context, rootNavigator: true);
        if (rootNavigator.canPop()) {
          rootNavigator.pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('APK скачан. Запускаем установщик...')),
        );
      }
      await dialogFuture;
    } catch (e) {
      if (context.mounted) {
        final rootNavigator = Navigator.of(context, rootNavigator: true);
        if (rootNavigator.canPop()) {
          rootNavigator.pop();
        }
      }
      await dialogFuture;

      if (e is UnknownSourcesPermissionException) {
        if (context.mounted) {
          await _showUnknownSourcesDialog(context);
        }
        return;
      }
      rethrow;
    } finally {
      progress.dispose();
    }
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
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
