import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/services/app_update_service.dart';
import '../../core/services/device_info_service.dart';
import '../../domain/entities/node_status.dart';
import '../../domain/entities/vpn_status.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/status_card.dart';
import '../widgets/vpn_toggle_button.dart';
import 'home_cubit.dart';
import 'home_state.dart';

/// Main dashboard screen:
/// VPN toggle, node status, balance, shared traffic.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static bool _sessionAutoUpdateChecked = false;
  bool _backgroundPromptChecked = false;
  bool _updateChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_backgroundPromptChecked) return;
    _backgroundPromptChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showBackgroundPermissionPromptIfNeeded();
      _checkForAppUpdateIfNeeded();
    });
  }

  Future<void> _showBackgroundPermissionPromptIfNeeded() async {
    final isUnrestricted =
        await DeviceInfoService.isIgnoringBatteryOptimizations();
    if (isUnrestricted || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171A21),
          title: const Text(
            'Разрешите работу в фоне',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Чтобы узел не отключался при выключенном экране, включите режим "Без ограничений" для ByteAway в настройках батареи.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Позже'),
            ),
            ElevatedButton(
              onPressed: () async {
                await DeviceInfoService.openBatteryOptimizationSettings();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Открыть настройки'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkForAppUpdateIfNeeded() async {
    if (_updateChecked || _sessionAutoUpdateChecked) return;
    _updateChecked = true;
    _sessionAutoUpdateChecked = true;

    try {
      final installedFromCache =
          await AppUpdateService.installPendingCachedUpdateIfAny();
      if (installedFromCache || !mounted) {
        return;
      }

      final update = await AppUpdateService.checkForUpdates();
      if (update == null || !mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !update.mandatory,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF171A21),
            title: const Text(
              'Доступно обновление',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            content: Text(
              'Новая версия ${update.version} (build ${update.buildNumber}) готова к установке.\n\n'
              'Изменения:\n${_formatChangelog(update.changelog)}',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              if (!update.mandatory)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Позже'),
                ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Скачиваем обновление...')),
                  );

                  try {
                    await _downloadAndInstallWithProgress(update);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Обновление не установлено: $e')),
                    );
                  }
                },
                child: const Text('Обновить'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      // Silent failure for auto-check.
    }
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

  Future<void> _downloadAndInstallWithProgress(AppUpdateInfo update) async {
    if (!mounted) return;

    final progress = ValueNotifier<double>(0);
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171A21),
          title: const Text(
            'Скачивание обновления',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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

      if (mounted) {
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
      if (mounted) {
        final rootNavigator = Navigator.of(context, rootNavigator: true);
        if (rootNavigator.canPop()) {
          rootNavigator.pop();
        }
      }
      await dialogFuture;

      if (e is UnknownSourcesPermissionException) {
        await _showUnknownSourcesDialog();
        return;
      }
      rethrow;
    } finally {
      progress.dispose();
    }
  }

  Future<void> _showUnknownSourcesDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171A21),
          title: const Text(
            'Разрешите установку APK',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          final width = MediaQuery.of(context).size.width;
          final isWide = width >= 1000;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              _buildHeader(context),
                              const SizedBox(height: 34),
                              VpnToggleButton(
                                isConnected: state.vpnStatus.isActive,
                                isLoading: state.vpnStatus.state ==
                                        VpnConnectionState.connecting ||
                                    state.vpnStatus.state ==
                                        VpnConnectionState.disconnecting,
                                onPressed: () =>
                                    context.read<HomeCubit>().toggleVpn(),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                state.vpnStatus.isActive
                                    ? 'ПОДКЛЮЧЕНО'
                                    : 'ОТКЛЮЧЕНО',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.w800,
                                      color: state.vpnStatus.isActive
                                          ? AppTheme.success
                                          : AppTheme.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 6,
                          child: Column(
                            children: [
                              ..._buildStatusCards(context, state),
                              if (state.error != null) ...[
                                const SizedBox(height: 20),
                                _buildError(state.error!),
                              ],
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 40),
                        VpnToggleButton(
                          isConnected: state.vpnStatus.isActive,
                          isLoading: state.vpnStatus.state ==
                                  VpnConnectionState.connecting ||
                              state.vpnStatus.state ==
                                  VpnConnectionState.disconnecting,
                          onPressed: () => context.read<HomeCubit>().toggleVpn(),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.vpnStatus.isActive ? 'ПОДКЛЮЧЕНО' : 'ОТКЛЮЧЕНО',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                letterSpacing: 2,
                                fontWeight: FontWeight.w800,
                                color: state.vpnStatus.isActive
                                    ? AppTheme.success
                                    : AppTheme.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 40),
                        ..._buildStatusCards(context, state),
                        if (state.error != null) ...[
                          const SizedBox(height: 20),
                          _buildError(state.error!),
                        ],
                        const SizedBox(height: 40),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildStatusCards(BuildContext context, HomeState state) {
    final nodeState = state.nodeToggleOn &&
            state.nodeStatus.state == NodeConnectionState.inactive
        ? NodeConnectionState.connecting
        : state.nodeStatus.state;

    return [
      StatusCard(
        title: 'Статус узла',
        value: _nodeStateLabel(nodeState),
        subtitle: state.nodeStatus.isActive
            ? '${state.nodeStatus.activeSessions} сес. • ${state.nodeStatus.currentSpeedMbps.toStringAsFixed(1)} Mbps'
            : (state.nodeToggleOn
                ? 'Удерживаем подключение узла...'
                : 'Поделитесь трафиком, чтобы заработать'),
        icon: Icons.cell_tower_rounded,
        iconColor: (state.nodeStatus.isActive || state.nodeToggleOn)
            ? AppTheme.success
            : AppTheme.textSecondary,
        trailing: Switch(
          value: state.nodeToggleOn,
          onChanged: (_) => context.read<HomeCubit>().toggleNode(),
        ),
      ),
      const SizedBox(height: 12),
      StatusCard(
        title: 'Заработано сегодня',
        value: '${state.todaySharedGb.toStringAsFixed(3)} GB',
        subtitle: state.balance != null
            ? 'Эквивалент: \$${(state.todaySharedGb * 5.0).toStringAsFixed(2)}'
            : 'Ожидание данных...',
        icon: Icons.auto_graph_rounded,
        iconColor: AppTheme.primary,
      ),
      const SizedBox(height: 12),
      StatusCard(
        title: 'Осталось подписки',
        value: state.balance != null
            ? _formatRemaining(state.balance!.vpnSecondsRemaining)
            : '—',
        subtitle: state.balance != null
            ? _buildTariffSubtitle(state.balance!.vpnPendingDays)
            : 'Тариф: Business Free',
        icon: Icons.verified_user_rounded,
        iconColor: AppTheme.accent,
        trailing: state.isBalanceLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white24),
                onPressed: () => context.read<HomeCubit>().fetchBalance(),
              ),
      ),
      if (state.balance != null && state.balance!.tier == 'free') ...[
        const SizedBox(height: 12),
        StatusCard(
          title: 'Бесплатный трафик (сегодня)',
          value: _formatBytes(state.balance!.freeDailyRemainingBytes),
          subtitle:
              'Использовано: ${_formatBytes(state.balance!.freeDailyUsedBytes)} из ${_formatBytes(state.balance!.freeDailyLimitBytes)}',
          icon: Icons.data_usage_rounded,
          iconColor: AppTheme.success,
        ),
      ],
    ];
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) =>
              AppTheme.primaryGradient.createShader(bounds),
          child: Text(
            'ByteAway',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                  color: Colors.white,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _nodeStateLabel(NodeConnectionState s) {
    switch (s) {
      case NodeConnectionState.active:
        return 'Активен';
      case NodeConnectionState.connecting:
        return 'Подключение...';
      case NodeConnectionState.conditionWait:
        return 'Ожидание WiFi + Зарядки';
      case NodeConnectionState.error:
        return 'Ошибка';
      case NodeConnectionState.inactive:
        return 'Неактивен';
    }
  }

  String _formatRemaining(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    if (safe <= 0) return '0 дней';
    final days = safe ~/ 86400;
    final hours = (safe % 86400) ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    if (days > 0) {
      return '$days дн ${hours}ч';
    }
    return '${hours}ч ${minutes}м';
  }

  String _buildTariffSubtitle(int pendingDays) {
    if (pendingDays > 0) {
      return 'Ожидает активации: $pendingDays дн';
    }
    return 'Тариф: Business Free';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }
}
