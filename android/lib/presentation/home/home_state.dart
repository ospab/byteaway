import 'package:equatable/equatable.dart';
import '../../domain/entities/balance.dart';
import '../../domain/entities/node_status.dart';
import '../../domain/entities/vpn_status.dart';

/// Home screen state — combines VPN, node, and balance data.
class HomeState extends Equatable {
  final VpnStatus vpnStatus;
  final NodeStatus nodeStatus;
  final Balance? balance;
  final bool isBalanceLoading;
  final String? error;

  const HomeState({
    this.vpnStatus = const VpnStatus.disconnected(),
    this.nodeStatus = const NodeStatus.inactive(),
    this.balance,
    this.isBalanceLoading = false,
    this.error,
  });

  HomeState copyWith({
    VpnStatus? vpnStatus,
    NodeStatus? nodeStatus,
    Balance? balance,
    bool? isBalanceLoading,
    String? error,
  }) {
    return HomeState(
      vpnStatus: vpnStatus ?? this.vpnStatus,
      nodeStatus: nodeStatus ?? this.nodeStatus,
      balance: balance ?? this.balance,
      isBalanceLoading: isBalanceLoading ?? this.isBalanceLoading,
      error: error,
    );
  }

  @override
  List<Object?> get props =>
      [vpnStatus, nodeStatus, balance, isBalanceLoading, error];
}
