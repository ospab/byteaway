import 'package:equatable/equatable.dart';
import '../../domain/entities/balance.dart';
import '../../domain/entities/node_status.dart';
import '../../domain/entities/vpn_status.dart';

/// Home screen state — combines VPN, node, and balance data.
class HomeState extends Equatable {
  final VpnStatus vpnStatus;
  final NodeStatus nodeStatus;
  final bool nodeToggleOn;
  final Balance? balance;
  final double todaySharedGb;
  final bool isBalanceLoading;
  final String? error;

  const HomeState({
    this.vpnStatus = const VpnStatus.disconnected(),
    this.nodeStatus = const NodeStatus.inactive(),
    this.nodeToggleOn = false,
    this.balance,
    this.todaySharedGb = 0.0,
    this.isBalanceLoading = false,
    this.error,
  });

  HomeState copyWith({
    VpnStatus? vpnStatus,
    NodeStatus? nodeStatus,
    bool? nodeToggleOn,
    Balance? balance,
    double? todaySharedGb,
    bool? isBalanceLoading,
    String? error,
  }) {
    return HomeState(
      vpnStatus: vpnStatus ?? this.vpnStatus,
      nodeStatus: nodeStatus ?? this.nodeStatus,
      nodeToggleOn: nodeToggleOn ?? this.nodeToggleOn,
      balance: balance ?? this.balance,
      todaySharedGb: todaySharedGb ?? this.todaySharedGb,
      isBalanceLoading: isBalanceLoading ?? this.isBalanceLoading,
      error: error,
    );
  }

  @override
  List<Object?> get props =>
      [vpnStatus, nodeStatus, nodeToggleOn, balance, todaySharedGb, isBalanceLoading, error];
}
