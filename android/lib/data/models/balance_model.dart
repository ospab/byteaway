import '../../domain/entities/balance.dart';

/// JSON-serializable balance model for the data layer.
class BalanceModel {
  final String clientId;
  final double balanceUsd;

  const BalanceModel({required this.clientId, required this.balanceUsd});

  factory BalanceModel.fromJson(Map<String, dynamic> json) {
    return BalanceModel(
      clientId: json['client_id'] as String? ?? '',
      balanceUsd: (json['balance_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'balance_usd': balanceUsd,
      };

  /// Convert to domain entity.
  Balance toEntity() => Balance(
        clientId: clientId,
        balanceUsd: balanceUsd,
      );
}
