class Room {
  final int id;
  final int floorId;
  final String roomCode;
  final String roomName;
  final int deviceCount;
  final int activeAlerts;

  Room({
    required this.id,
    required this.floorId,
    required this.roomCode,
    required this.roomName,
    required this.deviceCount,
    required this.activeAlerts,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      floorId: json['floor_id'],
      roomCode: json['room_code'],
      roomName: json['room_name'],
      deviceCount: json['device_count'] ?? 0,
      activeAlerts: json['active_alerts'] ?? 0,
    );
  }
}
