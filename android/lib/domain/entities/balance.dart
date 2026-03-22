import 'package:equatable/equatable.dart';

/// Client balance entity.
class Balance extends Equatable {
  final String clientId;
  final double balanceUsd;

  /// Computed VPN days remaining (assuming $0.50/day).
  double get vpnDaysRemaining => balanceUsd / 0.50;

  const Balance({
    required this.clientId,
    required this.balanceUsd,
  });

  @override
  List<Object?> get props => [clientId, balanceUsd];
}
