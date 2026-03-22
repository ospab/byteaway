import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/vpn_status.dart';
import '../../domain/repositories/vpn_repository.dart';
import '../../domain/repositories/node_repository.dart';
import '../../domain/usecases/stats_usecases.dart';
import '../../domain/usecases/vpn_usecases.dart';
import '../../domain/usecases/node_usecases.dart';
import '../../data/datasources/auth_local_ds.dart';
import 'home_state.dart';

/// Cubit managing the main dashboard:
/// VPN toggle, node status, balance display.
class HomeCubit extends Cubit<HomeState> {
  final ConnectVpnUseCase _connectVpn;
  final DisconnectVpnUseCase _disconnectVpn;
  final StartNodeUseCase _startNode;
  final StopNodeUseCase _stopNode;
  final GetBalanceUseCase _getBalance;
  final VpnRepository _vpnRepository;
  final NodeRepository _nodeRepository;
  final AuthLocalDataSource _authLocalDs;

  StreamSubscription? _vpnSub;
  StreamSubscription? _nodeSub;
  Timer? _balanceTimer;

  HomeCubit({
    required ConnectVpnUseCase connectVpn,
    required DisconnectVpnUseCase disconnectVpn,
    required StartNodeUseCase startNode,
    required StopNodeUseCase stopNode,
    required GetBalanceUseCase getBalance,
    required VpnRepository vpnRepository,
    required NodeRepository nodeRepository,
    required AuthLocalDataSource authLocalDs,
  })  : _connectVpn = connectVpn,
        _disconnectVpn = disconnectVpn,
        _startNode = startNode,
        _stopNode = stopNode,
        _getBalance = getBalance,
        _vpnRepository = vpnRepository,
        _nodeRepository = nodeRepository,
        _authLocalDs = authLocalDs,
        super(const HomeState()) {
    _init();
  }

  void _init() {
    // Listen to VPN status stream
    _vpnSub = _vpnRepository.statusStream.listen((status) {
      emit(state.copyWith(vpnStatus: status));
    });

    // Listen to node status stream
    _nodeSub = _nodeRepository.statusStream.listen((status) {
      emit(state.copyWith(nodeStatus: status));
    });

    // Fetch balance immediately and refresh every 60s
    fetchBalance();
    _balanceTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => fetchBalance(),
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
      // Default sing-box config — this would come from the server in production
      const config = '{}'; // Placeholder for sing-box JSON config
      final success = await _connectVpn(config);
      if (!success) {
        emit(state.copyWith(
          vpnStatus: const VpnStatus(
            state: VpnConnectionState.error,
            errorMessage: 'Не удалось подключиться',
          ),
        ));
      }
    }
  }

  /// Toggle node sharing.
  Future<void> toggleNode() async {
    if (state.nodeStatus.isActive) {
      await _stopNode();
    } else {
      final token = _authLocalDs.getToken();
      final deviceId = _authLocalDs.getDeviceId();
      final speedLimit = _authLocalDs.getSpeedLimit();

      if (token == null) {
        emit(state.copyWith(error: 'Не авторизован'));
        return;
      }

      await _startNode(
        token: token,
        deviceId: deviceId,
        country: 'auto', // Auto-detect by IP on the server
        speedMbps: speedLimit,
      );
    }
  }

  @override
  Future<void> close() {
    _vpnSub?.cancel();
    _nodeSub?.cancel();
    _balanceTimer?.cancel();
    return super.close();
  }
}
