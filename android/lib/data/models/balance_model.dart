import '../../domain/entities/balance.dart';

/// JSON-serializable balance model for the data layer.
class BalanceModel {
  final String clientId;
  final double balanceUsd;
  final double vpnDaysRemaining;
  final int vpnSecondsRemaining;
  final int vpnPendingDays;
  final String tier;
  final int freeDailyLimitBytes;
  final int freeDailyUsedBytes;
  final int freeDailyRemainingBytes;

  const BalanceModel({
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

  factory BalanceModel.fromJson(Map<String, dynamic> json) {
    return BalanceModel(
      clientId: json['client_id'] as String? ?? '',
      balanceUsd: (json['balance_usd'] as num?)?.toDouble() ?? 0.0,
      vpnDaysRemaining: (json['vpn_days_remaining'] as num?)?.toDouble() ?? 0.0,
      vpnSecondsRemaining: (json['vpn_seconds_remaining'] as num?)?.toInt() ?? 0,
      vpnPendingDays: (json['vpn_pending_days'] as num?)?.toInt() ?? 0,
      tier: json['tier'] as String? ?? 'paid',
      freeDailyLimitBytes: (json['free_daily_limit_bytes'] as num?)?.toInt() ?? 0,
      freeDailyUsedBytes: (json['free_daily_used_bytes'] as num?)?.toInt() ?? 0,
      freeDailyRemainingBytes: (json['free_daily_remaining_bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'balance_usd': balanceUsd,
        'vpn_days_remaining': vpnDaysRemaining,
        'vpn_seconds_remaining': vpnSecondsRemaining,
        'vpn_pending_days': vpnPendingDays,
        'tier': tier,
        'free_daily_limit_bytes': freeDailyLimitBytes,
        'free_daily_used_bytes': freeDailyUsedBytes,
        'free_daily_remaining_bytes': freeDailyRemainingBytes,
      };

  /// Convert to domain entity.
  Balance toEntity() => Balance(
        clientId: clientId,
        balanceUsd: balanceUsd,
      vpnDaysRemaining: vpnDaysRemaining,
      vpnSecondsRemaining: vpnSecondsRemaining,
      vpnPendingDays: vpnPendingDays,
      tier: tier,
      freeDailyLimitBytes: freeDailyLimitBytes,
      freeDailyUsedBytes: freeDailyUsedBytes,
      freeDailyRemainingBytes: freeDailyRemainingBytes,
      );
}
