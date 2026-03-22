import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/stats_usecases.dart';
import 'statistics_state.dart';

/// Cubit managing traffic statistics — fetches and aggregates daily records.
class StatisticsCubit extends Cubit<StatisticsState> {
  final GetTrafficHistoryUseCase _getTrafficHistory;

  StatisticsCubit(this._getTrafficHistory)
      : super(const StatisticsInitial()) {
    loadStats();
  }

  /// Load traffic history for the last 30 days.
  Future<void> loadStats({int days = 30}) async {
    emit(const StatisticsLoading());

    try {
      final records = await _getTrafficHistory(days: days);

      final totalShared = records.fold<double>(
          0, (sum, r) => sum + r.sharedGb);
      final totalConsumed = records.fold<double>(
          0, (sum, r) => sum + r.consumedGb);
      final totalEarned = records.fold<double>(
          0, (sum, r) => sum + r.earnedUsd);

      emit(StatisticsLoaded(
        records: records,
        totalSharedGb: totalShared,
        totalConsumedGb: totalConsumed,
        totalEarnedUsd: totalEarned,
      ));
    } catch (e) {
      emit(StatisticsError(e.toString()));
    }
  }
}
