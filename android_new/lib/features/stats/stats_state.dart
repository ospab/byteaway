import 'package:equatable/equatable.dart';
import '../../core/models/traffic_record.dart';

class StatsState extends Equatable {
  final bool isLoading;
  final List<TrafficRecord> records;
  final String? error;

  const StatsState({
    required this.isLoading,
    required this.records,
    this.error,
  });

  factory StatsState.initial() => const StatsState(isLoading: false, records: []);

  StatsState copyWith({
    bool? isLoading,
    List<TrafficRecord>? records,
    String? error,
  }) {
    return StatsState(
      isLoading: isLoading ?? this.isLoading,
      records: records ?? this.records,
      error: error,
    );
  }

  @override
  List<Object?> get props => [isLoading, records, error];
}
