import '../../domain/entities/traffic_record.dart';

/// JSON-serializable traffic record model.
class TrafficRecordModel {
  final String date;
  final int bytesShared;
  final int bytesConsumed;
  final double earnedUsd;

  const TrafficRecordModel({
    required this.date,
    required this.bytesShared,
    required this.bytesConsumed,
    required this.earnedUsd,
  });

  factory TrafficRecordModel.fromJson(Map<String, dynamic> json) {
    return TrafficRecordModel(
      date: json['date'] as String? ?? '',
      bytesShared: json['bytes_shared'] as int? ?? 0,
      bytesConsumed: json['bytes_consumed'] as int? ?? 0,
      earnedUsd: (json['earned_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'bytes_shared': bytesShared,
        'bytes_consumed': bytesConsumed,
        'earned_usd': earnedUsd,
      };

  /// Convert to domain entity.
  TrafficRecord toEntity() => TrafficRecord(
        date: DateTime.tryParse(date) ?? DateTime.now(),
        bytesShared: bytesShared,
        bytesConsumed: bytesConsumed,
        earnedUsd: earnedUsd,
      );
}
