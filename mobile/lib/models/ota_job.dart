class OtaJob {
  OtaJob({
    required this.id,
    required this.targetType,
    required this.targetRef,
    required this.firmwareVersion,
    required this.status,
    required this.progress,
    required this.requestedBy,
    required this.createdAt,
  });

  final int id;
  final String targetType;
  final String targetRef;
  final String firmwareVersion;
  final String status;
  final int progress;
  final String requestedBy;
  final DateTime createdAt;

  factory OtaJob.fromJson(Map<String, dynamic> json) {
    return OtaJob(
      id: json['id'] as int,
      targetType: json['target_type'].toString(),
      targetRef: json['target_ref'].toString(),
      firmwareVersion: json['firmware_version'].toString(),
      status: (json['status'] ?? 'queued').toString(),
      progress: json['progress'] as int? ?? 0,
      requestedBy: (json['requested_by'] ?? 'system').toString(),
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}
