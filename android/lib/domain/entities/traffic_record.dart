import 'package:equatable/equatable.dart';

/// Daily traffic record for statistics.
class TrafficRecord extends Equatable {
  final DateTime date;
  final int bytesShared;       // bytes given as a node
  final int bytesConsumed;     // bytes used via VPN
  final double earnedUsd;

  double get sharedGb => bytesShared / 1073741824.0;
  double get consumedGb => bytesConsumed / 1073741824.0;

  const TrafficRecord({
    required this.date,
    required this.bytesShared,
    required this.bytesConsumed,
    required this.earnedUsd,
  });

  @override
  List<Object?> get props => [date, bytesShared, bytesConsumed, earnedUsd];
}
