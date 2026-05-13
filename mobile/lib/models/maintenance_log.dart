class MaintenanceLog {
  MaintenanceLog({
    required this.id,
    required this.roomId,
    required this.issue,
    required this.status,
    required this.createdAt,
    this.notes,
  });

  final int id;
  final int roomId;
  final String issue;
  final String status;
  final String? notes;
  final DateTime createdAt;

  factory MaintenanceLog.fromJson(Map<String, dynamic> json) {
    return MaintenanceLog(
      id: json['id'] as int,
      roomId: json['room_id'] as int,
      issue: json['issue'].toString(),
      status: (json['status'] ?? 'open').toString(),
      notes: json['notes']?.toString(),
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}
