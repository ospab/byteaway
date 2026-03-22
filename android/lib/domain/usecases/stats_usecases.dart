import '../entities/balance.dart';
import '../entities/traffic_record.dart';
import '../repositories/stats_repository.dart';

/// Fetch current client balance from master node.
class GetBalanceUseCase {
  final StatsRepository _repository;

  const GetBalanceUseCase(this._repository);

  Future<Balance> call() {
    return _repository.getBalance();
  }
}

/// Fetch traffic history for the specified number of days.
class GetTrafficHistoryUseCase {
  final StatsRepository _repository;

  const GetTrafficHistoryUseCase(this._repository);

  Future<List<TrafficRecord>> call({int days = 30}) {
    return _repository.getTrafficHistory(days: days);
  }
}
