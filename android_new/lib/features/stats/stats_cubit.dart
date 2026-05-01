import 'package:flutter_bloc/flutter_bloc.dart';
import '../../app/di.dart';
import '../../core/constants.dart';
import '../../core/models/traffic_record.dart';
import '../../core/network/api_client.dart';
import '../../core/services/log_service.dart';
import 'stats_state.dart';

class StatsCubit extends Cubit<StatsState> {
  StatsCubit() : super(StatsState.initial());

  final ApiClient _api = sl<ApiClient>();

  Future<void> loadStats({int days = 30}) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final json = await _api.getJson(AppConstants.statsEndpoint, query: {'days': days});
      final raw = json['records'] as List<dynamic>? ?? const [];
      final records = raw
          .map((e) => TrafficRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      records.sort((a, b) => a.date.compareTo(b.date));
      emit(state.copyWith(isLoading: false, records: records));
    } catch (e) {
      await LogService.write('stats.load error: $e');
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
