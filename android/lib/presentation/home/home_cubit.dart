import 'dart:convert';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/balance.dart';
import '../../domain/entities/node_status.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/repositories/vpn_repository.dart';
import '../../domain/repositories/node_repository.dart';
import '../../domain/usecases/stats_usecases.dart';
import '../../domain/usecases/vpn_usecases.dart';
import '../../domain/usecases/node_usecases.dart';
import '../../data/datasources/auth_local_ds.dart';
import '../../core/logger.dart';
import '../../core/services/device_info_service.dart';
import 'home_state.dart';

/// Cubit managing the main dashboard:
/// VPN toggle, node status, balance display.
class HomeCubit extends Cubit<HomeState> {
  final ConnectVpnUseCase _connectVpn;
  final DisconnectVpnUseCase _disconnectVpn;
  final StartNodeUseCase _startNode;
  final StopNodeUseCase _stopNode;
  final GetBalanceUseCase _getBalance;
  final GetTrafficHistoryUseCase _getTrafficHistory;
  final VpnRepository _vpnRepository;
  final NodeRepository _nodeRepository;
  final AuthLocalDataSource _authLocalDs;

  StreamSubscription? _vpnSub;
  StreamSubscription? _nodeSub;
  Timer? _balanceTimer;
  Timer? _statsTimer;
  Timer? _balanceCountdownTimer;

  static const double _bytesPerGb = 1073741824.0;
  double _todaySharedServerGb = 0.0;
  int _sessionSharedBaselineBytes = 0;
  bool _sessionBaselineInitialized = false;
  bool _nodeToggleCommandInFlight = false;

  HomeCubit({
    required ConnectVpnUseCase connectVpn,
    required DisconnectVpnUseCase disconnectVpn,
    required StartNodeUseCase startNode,
    required StopNodeUseCase stopNode,
    required GetBalanceUseCase getBalance,
    required GetTrafficHistoryUseCase getTrafficHistory,
    required VpnRepository vpnRepository,
    required NodeRepository nodeRepository,
    required AuthLocalDataSource authLocalDs,
  })  : _connectVpn = connectVpn,
        _disconnectVpn = disconnectVpn,
        _startNode = startNode,
        _stopNode = stopNode,
        _getBalance = getBalance,
      _getTrafficHistory = getTrafficHistory,
        _vpnRepository = vpnRepository,
        _nodeRepository = nodeRepository,
        _authLocalDs = authLocalDs,
        super(const HomeState()) {
    _init();
  }

  void _init() {
    // Listen to VPN status stream
    _vpnSub = _vpnRepository.statusStream.listen((status) {
      // Без логов для чистоты
      emit(state.copyWith(vpnStatus: status));
    });

    _nodeSub = _nodeRepository.statusStream.listen((status) {
      // Без логов для чистоты
      _emitNodeWithTodayShared(status);
    });

    // Fetch balance immediately and refresh every 60s
    fetchBalance();
    _refreshTodayShared();
    _balanceTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => fetchBalance(),
    );
    _balanceCountdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickBalanceCountdown(),
    );
    _statsTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _refreshTodayShared(),
    );
  }

  /// Fetch balance from server.
  Future<void> fetchBalance() async {
    emit(state.copyWith(isBalanceLoading: true));
    try {
      final balance = await _getBalance();
      emit(state.copyWith(balance: balance, isBalanceLoading: false));
    } catch (e) {
      emit(state.copyWith(isBalanceLoading: false, error: e.toString()));
    }
  }

  Future<void> _refreshTodayShared() async {
    try {
      final records = await _getTrafficHistory(days: 2);
      final now = DateTime.now();
      var todayBytes = 0;

      for (final item in records) {
        if (_isSameDay(item.date, now)) {
          todayBytes += item.bytesShared;
        }
      }

      _todaySharedServerGb = todayBytes / _bytesPerGb;
      _emitNodeWithTodayShared(state.nodeStatus);
    } catch (_) {
      // Keep previous known value if stats fetch fails transiently.
    }
  }

  void _emitNodeWithTodayShared(NodeStatus status) {
    final shouldKeepToggleOn = state.nodeToggleOn || status.isActive;
    final effectiveStatus = shouldKeepToggleOn &&
            (status.state == NodeConnectionState.inactive || status.state == NodeConnectionState.error)
        ? const NodeStatus(state: NodeConnectionState.connecting)
        : status;

    if (effectiveStatus.isActive) {
      if (!_sessionBaselineInitialized) {
        _sessionSharedBaselineBytes = effectiveStatus.totalBytesShared;
        _sessionBaselineInitialized = true;
      }
    } else {
      _sessionSharedBaselineBytes = 0;
      _sessionBaselineInitialized = false;
    }

    final liveBytes = effectiveStatus.isActive
        ? (effectiveStatus.totalBytesShared - _sessionSharedBaselineBytes).clamp(0, 1 << 62)
        : 0;
    final todaySharedGb = _todaySharedServerGb + (liveBytes / _bytesPerGb);

    emit(state.copyWith(
      nodeStatus: effectiveStatus,
      nodeToggleOn: shouldKeepToggleOn,
      todaySharedGb: todaySharedGb,
    ));
  }

  /// Toggle VPN connection.
  Future<void> toggleVpn() async {
    if (state.vpnStatus.isActive) {
      emit(state.copyWith(
        vpnStatus: const VpnStatus(state: VpnConnectionState.disconnecting),
      ));
      await _disconnectVpn();
    } else {
      emit(state.copyWith(
        vpnStatus: const VpnStatus(state: VpnConnectionState.connecting),
      ));
      try {
        final configMap = await _vpnRepository.getVpnConfig();
        final coreConfigJson = configMap['core_config_json'] as String?;
        if (coreConfigJson == null || coreConfigJson.trim().isEmpty) {
          AppLogger.log('VPN: empty core config received from server');
          emit(state.copyWith(
            vpnStatus: const VpnStatus(
              state: VpnConnectionState.error,
              errorMessage: 'Сервер вернул пустую VPN-конфигурацию Core',
            ),
          ));
          return;
        }

        final tier = configMap['tier'] as String? ?? 'free';
        final maxSpeed = configMap['max_speed_mbps'] as int? ?? 0;
        AppLogger.log(
            'VPN: config received, tier=$tier, maxSpeed=${maxSpeed}Mbps, coreConfigLength=${coreConfigJson.length}');

        final safeConfig = _normalizeCoreConfig(coreConfigJson);

        // Pass full JSON config down to the native Kotlin layer
        final success = await _connectVpn(safeConfig);
        if (!success) {
          AppLogger.log(
              'VPN: native start failed (permission/config/runtime error)');
          emit(state.copyWith(
            vpnStatus: const VpnStatus(
              state: VpnConnectionState.error,
              errorMessage:
                  'Не удалось подключить VPN. Выдайте разрешение VPN и повторите.',
            ),
          ));
        }
      } catch (e) {
        AppLogger.log('VPN: connect flow exception: $e');
        emit(state.copyWith(
          vpnStatus: VpnStatus(
            state: VpnConnectionState.error,
            errorMessage: 'Ошибка подключения VPN: $e',
          ),
        ));
      }
    }
  }

  /// Toggle node sharing.
  Future<void> toggleNode() async {
    if (_nodeToggleCommandInFlight) return;
    _nodeToggleCommandInFlight = true;

    try {
      if (state.nodeToggleOn) {
        emit(state.copyWith(
          nodeToggleOn: false,
          nodeStatus: const NodeStatus(state: NodeConnectionState.inactive),
        ));
      AppLogger.log('Node: stop requested');
      await _stopNode();
        return;
      }

      emit(state.copyWith(
        nodeToggleOn: true,
        nodeStatus: const NodeStatus(state: NodeConnectionState.connecting),
      ));

      final token = _authLocalDs.getToken();
      final storedDeviceId = _authLocalDs.getDeviceId();
      final speedLimit = _authLocalDs.getSpeedLimit();
      final transportMode = _authLocalDs.getNodeTransportMode();

      if (token == null) {
        emit(state.copyWith(nodeToggleOn: false));
        emit(state.copyWith(error: 'Не авторизован'));
        return;
      }

      final hardwareId = await DeviceInfoService.getHardwareId();
      final deviceId = _isValidDeviceId(hardwareId)
          ? hardwareId
          : storedDeviceId;

      if (!_isValidDeviceId(deviceId)) {
        emit(state.copyWith(nodeToggleOn: false));
        emit(state.copyWith(error: 'Не удалось получить HWID устройства'));
        return;
      }

      if (deviceId != storedDeviceId) {
        await _authLocalDs.saveDeviceId(deviceId!);
      }

      AppLogger.log(
        'Node: start requested, deviceId=$deviceId speed=${speedLimit}Mbps transport=$transportMode',
      );

      // Get real device country and connection type
      final country = await DeviceInfoService.getCountryCode();
      final connType = await DeviceInfoService.getConnectionType();
      String? coreConfigJson;

      try {
        final vpnCfg = await _vpnRepository.getVpnConfig(useRuEgress: true);
        final raw = vpnCfg['core_config_json'] as String?;
        if (raw != null && raw.trim().isNotEmpty) {
          coreConfigJson = raw;
        }
      } catch (e) {
        AppLogger.log('Node: failed to fetch core config for anti-block fallback: $e');
      }

      final normalizedTransport = transportMode.trim().toLowerCase();
      final requiresProxyConfig = normalizedTransport == 'ws' || normalizedTransport == 'hy2';
      final hasProxyConfig = coreConfigJson != null && coreConfigJson.trim().isNotEmpty;
      final recommendedMtu = normalizedTransport == 'quic' ? 1280 : 1420;

      if (requiresProxyConfig && !hasProxyConfig) {
        emit(state.copyWith(
          nodeToggleOn: false,
          nodeStatus: const NodeStatus(state: NodeConnectionState.error),
          error: 'Для режима WS/HY2 не получена конфигурация прокси. Проверьте сеть и повторите.',
        ));
        return;
      }

      if (!hasProxyConfig) {
        AppLogger.log('Node: core config unavailable, QUIC will start with direct fallback');
      }

      AppLogger.log('Node: detected country=$country, connection=$connType');

      final started = await _startNode(
        token: token,
        deviceId: deviceId!,
        country: country,
        transportMode: transportMode,
        connType: connType,
        speedMbps: speedLimit,
        mtu: recommendedMtu,
        masterWsUrl: null,
        coreConfigJson: coreConfigJson,
      );

      if (!started) {
        emit(state.copyWith(
          nodeToggleOn: false,
          nodeStatus: const NodeStatus(
            state: NodeConnectionState.error,
            errorMessage: 'Не удалось запустить узел',
          ),
          error: 'Нативный сервис отклонил запуск узла. Откройте логи и повторите.',
        ));
      }
    } finally {
      _nodeToggleCommandInFlight = false;
    }
  }

  void _tickBalanceCountdown() {
    final current = state.balance;
    if (current == null) return;
    if (current.vpnSecondsRemaining <= 0) return;

    final nextSeconds = current.vpnSecondsRemaining - 1;
    final nextDays = nextSeconds <= 0 ? 0.0 : (nextSeconds / 86400.0);

    emit(state.copyWith(
      balance: Balance(
        clientId: current.clientId,
        balanceUsd: current.balanceUsd,
        vpnDaysRemaining: nextDays,
        vpnSecondsRemaining: nextSeconds,
        vpnPendingDays: current.vpnPendingDays,
        tier: current.tier,
        freeDailyLimitBytes: current.freeDailyLimitBytes,
        freeDailyUsedBytes: current.freeDailyUsedBytes,
        freeDailyRemainingBytes: current.freeDailyRemainingBytes,
      ),
    ));
  }

  String _normalizeCoreConfig(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return rawJson;

      final outbounds = decoded['outbounds'];
      if (outbounds is! List) return rawJson;

      for (final item in outbounds) {
        if (item is! Map<String, dynamic>) continue;
        final streamSettings = item['streamSettings'];
        if (streamSettings is! Map<String, dynamic>) continue;
        if ((streamSettings['security'] as String?)?.toLowerCase() != 'reality') continue;

        final realitySettings =
            (streamSettings['realitySettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};

        String fallbackHost = 'google.com';

        final vnext = ((item['settings'] as Map<String, dynamic>?)?['vnext']);
        if (vnext is List && vnext.isNotEmpty && vnext.first is Map<String, dynamic>) {
          final address = (vnext.first as Map<String, dynamic>)['address'] as String?;
          if (address != null && address.trim().isNotEmpty) {
            fallbackHost = address.trim();
          }
        }

        final dest = realitySettings['dest'] as String?;
        if (dest != null && dest.trim().isNotEmpty && dest.contains(':')) {
          final host = dest.split(':').first.trim();
          if (host.isNotEmpty) {
            fallbackHost = host;
          }
        }

        var serverName = (realitySettings['serverName'] as String?)?.trim() ?? '';
        if (serverName.isEmpty) {
          serverName = fallbackHost;
          realitySettings['serverName'] = serverName;
        }

        var shortId = (realitySettings['shortId'] as String?)?.trim() ?? '';
        if (shortId.isEmpty) {
          final shortIdsRaw = realitySettings['shortIds'];
          if (shortIdsRaw is List && shortIdsRaw.isNotEmpty) {
            final first = shortIdsRaw.first?.toString().trim() ?? '';
            if (first.isNotEmpty) shortId = first;
          }
          if (shortId.isEmpty) {
            shortId = '0123456789abcdef';
          }
          realitySettings['shortId'] = shortId;
        }

        final shortIdsRaw = realitySettings['shortIds'];
        if (shortIdsRaw is! List || shortIdsRaw.isEmpty) {
          realitySettings['shortIds'] = [shortId];
        }

        final serverNamesRaw = realitySettings['serverNames'];
        if (serverNamesRaw is! List || serverNamesRaw.isEmpty) {
          realitySettings['serverNames'] = [serverName];
        }

        final finalDest = (realitySettings['dest'] as String?)?.trim() ?? '';
        if (finalDest.isEmpty) {
          realitySettings['dest'] = '$serverName:443';
        }

        streamSettings['realitySettings'] = realitySettings;
      }

      return jsonEncode(decoded);
    } catch (e) {
      AppLogger.log('VPN: failed to normalize core config, using raw config. Error: $e');
      return rawJson;
    }
  }

  @override
  Future<void> close() {
    _vpnSub?.cancel();
    _nodeSub?.cancel();
    _balanceTimer?.cancel();
    _statsTimer?.cancel();
    _balanceCountdownTimer?.cancel();
    return super.close();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isValidDeviceId(String? id) {
    if (id == null) return false;
    final value = id.trim().toLowerCase();
    if (value.isEmpty) return false;
    if (value == 'unknown-hwid') return false;
    if (value == 'unknown-device') return false;
    return true;
  }
}
