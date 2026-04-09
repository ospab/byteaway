import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../../core/constants.dart';
import '../widgets/status_card.dart';

class VpnClientScreen extends StatefulWidget {
  const VpnClientScreen({super.key});

  @override
  State<VpnClientScreen> createState() => _VpnClientScreenState();
}

class _VpnClientScreenState extends State<VpnClientScreen> {
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isNodeActive = false;
  String? _errorMessage;
  DateTime? _connectedAt;
  String _serverLocation = 'Франкфурт';
  double _sharedTrafficGB = 0.0;
  double _currentSpeedMbps = 0.0;
  int _vpnDaysRemaining = 30;
  double _balanceUsd = 2.50;
  int _activeSessions = 0;

  final Dio _dio = Dio();
  Timer? _statsTimer;

  // Platform channel для связи с Go ядром
  static const platform = MethodChannel('com.ospab.byteaway/vpn');

  @override
  void initState() {
    super.initState();

    // Initialize API client
    _dio.options.baseUrl = AppConstants.baseUrl;
    _dio.options.headers['Authorization'] = 'Bearer test_key_123';

    // Get current state
    _getCurrentState();

    // Не будем автоматически обновлять статистику - это засирает логи
    // _startStatsUpdates();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  void _startStatsUpdates() {
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isConnected || _isNodeActive) {
        _updateStats();
      }
    });
  }

  Future<void> _getCurrentState() async {
    try {
      // Get balance
      final balanceResponse = await _dio.get('/api/v1/balance');
      final balanceData = balanceResponse.data;
      setState(() {
        _balanceUsd = (balanceData['balance_usd'] ?? 0.0).toDouble();
        _vpnDaysRemaining = (balanceData['vpn_days_remaining'] ?? 0).toInt();
      });

      // Get current VPN state from native service
      // This would be implemented via platform channel
    } catch (e) {
      // Без логов ошибок для чистоты
    }
  }

  Future<void> _updateStats() async {
    try {
      // Get real stats from master node
      final statsResponse = await _dio.get('/api/v1/stats');
      final statsData = statsResponse.data;

      if (mounted) {
        setState(() {
          _sharedTrafficGB = (statsData['shared_traffic_gb'] ?? 0.0).toDouble();
          _currentSpeedMbps =
              (statsData['current_speed_mbps'] ?? 0.0).toDouble();
          _activeSessions = (statsData['active_sessions'] ?? 0).toInt();
        });
      }
    } catch (e) {
      // Без логов ошибок для чистоты
      // Fallback to simulation if API is not available
      if (_isNodeActive && mounted) {
        setState(() {
          _sharedTrafficGB += 0.01;
          _currentSpeedMbps = 2.5 + (DateTime.now().millisecond % 100) / 100;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ── Header ───────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF00D4AA), Color(0xFF00BCD4)],
                    ).createShader(bounds),
                    child: const Text(
                      'ByteAway',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
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
                          color: _isConnected
                              ? const Color(0xFF00C896)
                              : const Color(0xFF8E92A3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isConnected ? 'VPN активен' : 'Отключено',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // ── VPN Toggle Button ────────────────
              GestureDetector(
                onTap: _toggleVpn,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isConnected
                          ? [
                              const Color(0xFF00C896),
                              const Color(0xFF00C896).withOpacity(0.7),
                            ]
                          : [
                              const Color(0xFF00D4AA),
                              const Color(0xFF00BCD4),
                            ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _isConnected
                            ? const Color(0xFF00C896).withOpacity(0.3)
                            : const Color(0xFF00D4AA).withOpacity(0.15),
                        blurRadius: _isConnected ? 40 : 20,
                        spreadRadius: _isConnected ? 5 : 0,
                      ),
                    ],
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Icon(
                          _isConnected
                              ? Icons.power_settings_new
                              : Icons.power_settings_new_outlined,
                          size: 56,
                          color: Colors.white,
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // VPN status label
              Text(
                _isConnected
                    ? 'Подключено к VPN'
                    : 'Нажмите для подключения к VPN',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 24),

              // ── Подробное описание ───────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Как это работает?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• VPN обеспечивает полную конфиденциальность вашего трафика\n'
                      '• Узел шеринга работает только на WiFi при зарядке\n'
                      '• Вы получаете бесплатный VPN, делая часть своего канала доступной\n'
                      '• B2B клиенты используют ваши резидентные IP для своих задач',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // ── Status Cards ─────────────────────
              // Balance / VPN Days
              StatusCard(
                title: 'Баланс VPN',
                value: '$_vpnDaysRemaining дней',
                subtitle: '\$${_balanceUsd.toStringAsFixed(2)}',
                icon: Icons.calendar_today_rounded,
                iconColor: const Color(0xFF00D4AA),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      color: Color(0xFF8E92A3), size: 20),
                  onPressed: _getCurrentState,
                ),
              ),

              const SizedBox(height: 12),

              // Node Status
              StatusCard(
                title: 'Статус узла',
                value: _isNodeActive ? 'Активен (WiFi)' : 'Неактивен',
                subtitle: _isNodeActive
                    ? '${(_currentSpeedMbps * 1024).round()} KB/s • ${_sharedTrafficGB.toStringAsFixed(2)} GB • $_activeSessions сессий'
                    : null,
                icon: _isNodeActive
                    ? Icons.cell_tower_rounded
                    : Icons.cell_tower_outlined,
                iconColor: _isNodeActive
                    ? const Color(0xFF00C896)
                    : const Color(0xFF8E92A3),
                trailing: Switch(
                  value: _isNodeActive,
                  onChanged: _toggleNode,
                ),
              ),

              const SizedBox(height: 12),

              // Traffic Shared
              StatusCard(
                title: 'Отдано сегодня',
                value: '${_sharedTrafficGB.toStringAsFixed(2)} GB',
                subtitle: _isNodeActive
                    ? 'Текущая скорость: ${_currentSpeedMbps.toStringAsFixed(1)} Mbps'
                    : 'Узел неактивен',
                icon: Icons.cloud_upload_outlined,
                iconColor: const Color(0xFF00BCD4),
              ),

              // Error display
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF5252).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFFF5252), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFFF5252),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Battery Optimization Tip
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.battery_saver_rounded,
                            color: Colors.amber.withOpacity(0.8), size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Совет по стабильности',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Если VPN отключается в фоне, отключите "Оптимизацию батареи" для ByteAway в настройках системы.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleVpn() async {
    if (_isConnected) {
      // Disconnect
      setState(() {
        _isLoading = true;
      });

      try {
        // Вызываем нативный метод для остановки VPN
        await platform.invokeMethod('stopVpn');

        setState(() {
          _isConnected = false;
          _isLoading = false;
          _connectedAt = null;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Ошибка отключения: $e';
        });
      }
    } else {
      // Connect
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        // Получаем конфиг с мастер ноды
        final configResponse = await _dio.get('/api/v1/vpn/config');
        final config = configResponse.data;

        // Простая конфигурация Xray-core без лишних параметров
        final vpnConfig = {
          'server': config['server_address'] ?? 'fr.vpn.byteaway.com',
          'port': config['port'] ?? 443,
          'uuid': config['uuid'] ?? '12345678-1234-1234-1234-123456789abc',
          'flow': config['flow'] ?? 'xtls-rprx-vision',
          'reality': config['reality'] ??
              {
                'enabled': true,
                'server_name': 'microsoft.com',
                'private_key':
                    'U8mZFj3KZx8j9q9m9k8j7f6d5s4a3b2c1d0e9f8g7h6i5j4k3l2m1n0o9p8q7',
                'short_id': ['abc123']
              },
          'dns': ['1.1.1.1', '8.8.8.8'],
          'mtu': 1280,
        };

        // Вызываем нативный метод для запуска VPN
        await platform.invokeMethod('startVpn', {
          'config': jsonEncode(vpnConfig),
          'dns': vpnConfig['dns'],
          'mtu': vpnConfig['mtu'],
        });

        setState(() {
          _isConnected = true;
          _isLoading = false;
          _connectedAt = DateTime.now();
          _serverLocation = config['location'] ?? 'Франкфурт';
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Ошибка подключения: $e';
        });
      }
    }
  }

  Future<void> _toggleNode(bool value) async {
    setState(() {
      _isNodeActive = value;
      if (!value) {
        _currentSpeedMbps = 0.0;
      }
    });

    try {
      if (value) {
        // Start sharing node - connect to master node via WebSocket
        // TODO: Implement WebSocket connection to master node
        print('Starting sharing node...');
      } else {
        // Stop sharing node
        // TODO: Close WebSocket connection
        print('Stopping sharing node...');
      }
    } catch (e) {
      setState(() {
        _isNodeActive = !value; // Revert on error
        _errorMessage = 'Ошибка узла: $e';
      });
    }
  }

  String _getVpnStatusLabel() {
    if (_isConnected) return 'Активно';
    if (_isLoading) return 'Подключение...';
    return 'Неактивно';
  }

  IconData _getVpnStatusIcon() {
    if (_isConnected) return Icons.shield_rounded;
    if (_isLoading) return Icons.sync;
    return Icons.shield_outlined;
  }

  Color _getVpnStatusColor() {
    if (_isConnected) return const Color(0xFF00C896);
    if (_isLoading) return const Color(0xFF00D4AA);
    return const Color(0xFF8E92A3);
  }

  String _getConnectedDuration() {
    if (_connectedAt != null) {
      final duration = DateTime.now().difference(_connectedAt!);
      final h = duration.inHours;
      final m = duration.inMinutes % 60;
      if (h > 0) return '$hч $mм';
      return '$mм';
    }
    return '—';
  }
}
