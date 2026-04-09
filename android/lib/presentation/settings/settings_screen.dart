import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/app_update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_scaffold.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';

/// Settings screen: speed limit, WiFi-only, Kill Switch.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTapCount = 0;
  bool _hiddenSettingsUnlocked = false;

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      title: 'Настройки',
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 100, 20, 20),
            children: [
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

              _buildGlassCard(
                context,
                child: Row(
                  children: [
                    const Icon(Icons.wifi_rounded, color: AppTheme.success, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Только WiFi', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
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

              const SizedBox(height: 32),

              // ── Section: Security ────────────────
              _buildSectionHeader(context, 'Безопасность'),
              const SizedBox(height: 12),

              _buildGlassCard(
                context,
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded, color: AppTheme.error, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Kill Switch', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                          Text('Блокировка при обрыве VPN', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: state.killSwitch,
                      onChanged: (v) => context.read<SettingsCubit>().toggleKillSwitch(v),
                    ),
                  ],
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
                      future: AppUpdateService.getDisplayVersion(),
                      builder: (context, snapshot) {
                        final version = snapshot.data ?? '...';
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _onVersionTapped(context),
                          child: _InfoRow(label: 'Версия', value: version),
                        );
                      },
                    ),
                    if (_hiddenSettingsUnlocked) ...[
                      const Divider(color: Colors.white10, height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Скрытые настройки транспорта',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Для РФ: WS идет внутри локального VPN-туннеля (Xray SOCKS).',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: state.nodeTransportMode,
                                    dropdownColor: const Color(0xFF171A21),
                                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                                    iconEnabledColor: AppTheme.primary,
                                items: const [
                                      DropdownMenuItem(value: 'quic', child: Text('QUIC (прямой, быстрый)')),
                                      DropdownMenuItem(value: 'ws', child: Text('WS через VPN-туннель (для РФ ✓)')),
                                      DropdownMenuItem(value: 'hy2', child: Text('HY2 relay + SOCKS')),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      context.read<SettingsCubit>().setNodeTransportMode(value);
                                    },
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Text(
                                      'VPN MTU',
                                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                    ),
                                    const Spacer(),
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        value: state.vpnMtu,
                                        dropdownColor: const Color(0xFF171A21),
                                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                                        iconEnabledColor: AppTheme.primary,
                                        items: const [
                                          DropdownMenuItem(value: 1280, child: Text('1280 (safe)')),
                                          DropdownMenuItem(value: 1380, child: Text('1380')),
                                          DropdownMenuItem(value: 1480, child: Text('1480')),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          context.read<SettingsCubit>().setVpnMtu(value);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Divider(color: Colors.white10, height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.system_update_alt_rounded,
                          color: AppTheme.accent),
                      title: const Text('Проверить обновление',
                          style: TextStyle(
                              color: AppTheme.textPrimary, fontSize: 15)),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.white24),
                      onTap: () => _checkForUpdates(context),
                    ),
                    const Divider(color: Colors.white10, height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.telegram_rounded, color: AppTheme.primary),
                      title: const Text('Прокси для Telegram', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
                      subtitle: const Text(
                        'Ссылка: https://t.me/socks?server=127.0.0.1&port=10808',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _copyTelegramProxyLink(context),
                            child: const Text('Ссылка'),
                          ),
                          TextButton(
                            onPressed: () => _copyTelegramProxy(context),
                            child: const Text('Данные'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined, color: AppTheme.primary),
                      title: const Text('Журнал событий (Logs)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
                      onTap: () => context.push('/logs'),
                    ),
                  ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Скрытые настройки разблокированы')),
      );
      return;
    }

    final tapsLeft = 5 - _versionTapCount;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('До скрытых настроек: $tapsLeft')),
    );
  }

  Future<void> _copyTelegramProxy(BuildContext context) async {
    const host = '127.0.0.1';
    const port = 10808;
    const user = 'none';
    const pass = 'none';
    const payload = 'SOCKS5\nHost: $host\nPort: $port\nUsername: $user\nPassword: $pass\n\n'
        'Важно: локальный прокси доступен, когда запущен ByteAway сервис (VPN или Node).';

    await Clipboard.setData(const ClipboardData(text: payload));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Параметры прокси Telegram скопированы')),
    );
  }

  Future<void> _copyTelegramProxyLink(BuildContext context) async {
    const link = 'https://t.me/socks?server=127.0.0.1&port=10808';
    await Clipboard.setData(const ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка Telegram прокси скопирована')),
    );
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
