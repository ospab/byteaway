import 'package:equatable/equatable.dart';
import '../../domain/entities/traffic_record.dart';

/// Statistics screen state.
sealed class StatisticsState extends Equatable {
  const StatisticsState();

  @override
  List<Object?> get props => [];
}

class StatisticsInitial extends StatisticsState {
  const StatisticsInitial();
}

class StatisticsLoading extends StatisticsState {
  const StatisticsLoading();
}

class StatisticsLoaded extends StatisticsState {
  final List<TrafficRecord> records;
  final double totalSharedGb;
  final double totalConsumedGb;
  final double totalEarnedUsd;

  const StatisticsLoaded({
    required this.records,
    required this.totalSharedGb,
    required this.totalConsumedGb,
    required this.totalEarnedUsd,
  });

  @override
  List<Object?> get props =>
      [records, totalSharedGb, totalConsumedGb, totalEarnedUsd];
}

class StatisticsError extends StatisticsState {
  final String message;
  const StatisticsError(this.message);

  @override
  List<Object?> get props => [message];
}
