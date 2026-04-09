import 'package:equatable/equatable.dart';

/// Client balance entity.
class Balance extends Equatable {
  final String clientId;
  final double balanceUsd;
  final double vpnDaysRemaining;
  final int vpnSecondsRemaining;
  final int vpnPendingDays;
  final String tier;
  final int freeDailyLimitBytes;
  final int freeDailyUsedBytes;
  final int freeDailyRemainingBytes;

  const Balance({
    required this.clientId,
    required this.balanceUsd,
    required this.vpnDaysRemaining,
    this.vpnSecondsRemaining = 0,
    this.vpnPendingDays = 0,
    this.tier = 'paid',
    this.freeDailyLimitBytes = 0,
    this.freeDailyUsedBytes = 0,
    this.freeDailyRemainingBytes = 0,
  });

  @override
  List<Object?> get props => [
        clientId,
        balanceUsd,
        vpnDaysRemaining,
        vpnSecondsRemaining,
        vpnPendingDays,
        tier,
        freeDailyLimitBytes,
        freeDailyUsedBytes,
        freeDailyRemainingBytes,
      ];
}
