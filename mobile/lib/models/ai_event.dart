class AiEvent {
  AiEvent({
    required this.id,
    required this.roomId,
    required this.cameraId,
    required this.eventType,
    required this.confidence,
    required this.createdAt,
    required this.payload,
    this.snapshotUrl,
  });

  final int id;
  final int roomId;
  final String cameraId;
  final String eventType;
  final double confidence;
  final String? snapshotUrl;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  factory AiEvent.fromJson(Map<String, dynamic> json) {
    return AiEvent(
      id: json['id'] as int,
      roomId: json['room_id'] as int,
      cameraId: json['camera_id'].toString(),
      eventType: json['event_type'].toString(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      snapshotUrl: json['snapshot_url']?.toString(),
      createdAt: DateTime.parse(json['created_at'].toString()),
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  String get roomCode => payload['room_code']?.toString() ?? 'Room $roomId';
}
