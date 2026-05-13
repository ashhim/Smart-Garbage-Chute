class Device {
  Device({
    required this.id,
    required this.roomId,
    required this.deviceId,
    required this.deviceType,
    required this.firmwareVersion,
    required this.status,
    this.lastSeenAt,
    this.roomCode,
    this.roomName,
    this.zone,
    this.floorLevel,
    this.buildingCode,
    this.buildingName,
    this.openAlertCount = 0,
    this.lastEventType,
    this.lastEventAt,
  });

  final int id;
  final int roomId;
  final String deviceId;
  final String deviceType;
  final String firmwareVersion;
  final String status;
  final DateTime? lastSeenAt;
  final String? roomCode;
  final String? roomName;
  final String? zone;
  final int? floorLevel;
  final String? buildingCode;
  final String? buildingName;
  final int openAlertCount;
  final String? lastEventType;
  final DateTime? lastEventAt;

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as int,
      roomId: json['room_id'] as int,
      deviceId: json['device_id'].toString(),
      deviceType: json['device_type'].toString(),
      firmwareVersion: json['firmware_version'].toString(),
      status: (json['status'] ?? 'unknown').toString(),
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.tryParse(json['last_seen_at'].toString()),
      roomCode: json['room_code']?.toString(),
      roomName: json['room_name']?.toString(),
      zone: json['zone']?.toString(),
      floorLevel: json['floor_level'] as int?,
      buildingCode: json['building_code']?.toString(),
      buildingName: json['building_name']?.toString(),
      openAlertCount: json['open_alert_count'] as int? ?? 0,
      lastEventType: json['last_event_type']?.toString(),
      lastEventAt: json['last_event_at'] == null
          ? null
          : DateTime.tryParse(json['last_event_at'].toString()),
    );
  }

  bool get online => status.toLowerCase() == 'online';

  String get roomLabel {
    final code = roomCode ?? 'Room $roomId';
    if (roomName == null || roomName!.isEmpty) {
      return code;
    }
    return '$code - $roomName';
  }

  String get locationLabel {
    final building = buildingCode ?? buildingName;
    if (building == null && floorLevel == null) {
      return '--';
    }
    if (building == null) {
      return 'Level $floorLevel';
    }
    if (floorLevel == null) {
      return building;
    }
    return '$building / Level $floorLevel';
  }
}
