import '../entities/balance.dart';
import '../entities/traffic_record.dart';

/// Abstract stats repository — balance and traffic history.
abstract class StatsRepository {
  /// Fetch current balance from REST API.
  Future<Balance> getBalance();

  /// Fetch traffic history for the last [days] days.
  Future<List<TrafficRecord>> getTrafficHistory({int days = 30});
}
