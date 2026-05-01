class TrafficRecord {
  final DateTime date;
  final int bytesShared;
  final int bytesConsumed;
  final double earnedUsd;

  const TrafficRecord({
    required this.date,
    required this.bytesShared,
    required this.bytesConsumed,
    required this.earnedUsd,
  });

  double get sharedGb => bytesShared / 1073741824.0;
  double get consumedGb => bytesConsumed / 1073741824.0;

  factory TrafficRecord.fromJson(Map<String, dynamic> json) {
    return TrafficRecord(
      date: DateTime.parse(json['date'] as String),
      bytesShared: (json['bytes_shared'] as num?)?.toInt() ?? 0,
      bytesConsumed: (json['bytes_consumed'] as num?)?.toInt() ?? 0,
      earnedUsd: (json['earned_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
