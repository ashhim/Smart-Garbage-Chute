class Device {
  final int id;
  final int roomId;
  final String deviceId;
  final String deviceType;
  final String firmwareVersion;
  final DateTime? lastSeenAt;
  final bool online;

  Device({
    required this.id,
    required this.roomId,
    required this.deviceId,
    required this.deviceType,
    required this.firmwareVersion,
    this.lastSeenAt,
    required this.online,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'],
      roomId: json['room_id'],
      deviceId: json['device_id'],
      deviceType: json['device_type'],
      firmwareVersion: json['firmware_version'],
      lastSeenAt:
          json['last_seen_at'] != null
              ? DateTime.parse(json['last_seen_at'])
              : null,
      online: json['online'] ?? false,
    );
  }
}
