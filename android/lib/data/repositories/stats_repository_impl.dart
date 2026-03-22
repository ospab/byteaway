import '../../domain/entities/balance.dart';
import '../../domain/entities/traffic_record.dart';
import '../../domain/repositories/stats_repository.dart';
import '../datasources/balance_remote_ds.dart';
import '../datasources/stats_remote_ds.dart';

/// Concrete [StatsRepository] — fetches balance and traffic history from API.
class StatsRepositoryImpl implements StatsRepository {
  final BalanceRemoteDataSource _balanceDs;
  final StatsRemoteDataSource _statsDs;

  StatsRepositoryImpl(this._balanceDs, this._statsDs);

  @override
  Future<Balance> getBalance() async {
    final model = await _balanceDs.getBalance();
    return model.toEntity();
  }

  @override
  Future<List<TrafficRecord>> getTrafficHistory({int days = 30}) async {
    final models = await _statsDs.getTrafficHistory(days: days);
    return models.map((m) => m.toEntity()).toList();
  }
}
