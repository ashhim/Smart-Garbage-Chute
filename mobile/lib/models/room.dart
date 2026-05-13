class Room {
  Room({
    required this.id,
    required this.floorId,
    required this.roomCode,
    required this.name,
    required this.zone,
    this.buildingCode,
    this.buildingName,
    this.floorLevel,
    this.devicesCount = 0,
    this.onlineDevices = 0,
    this.openAlertCount = 0,
    this.primaryDeviceId,
    this.primaryDeviceStatus,
    this.lastEventType,
    this.lastEventAt,
    this.status = 'normal',
  });

  final int id;
  final int floorId;
  final String roomCode;
  final String name;
  final String zone;
  final String? buildingCode;
  final String? buildingName;
  final int? floorLevel;
  final int devicesCount;
  final int onlineDevices;
  final int openAlertCount;
  final String? primaryDeviceId;
  final String? primaryDeviceStatus;
  final String? lastEventType;
  final DateTime? lastEventAt;
  final String status;

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as int,
      floorId: json['floor_id'] as int,
      roomCode: json['room_code'].toString(),
      name: (json['name'] ?? '').toString(),
      zone: (json['zone'] ?? 'chute-room').toString(),
      buildingCode: json['building_code']?.toString(),
      buildingName: json['building_name']?.toString(),
      floorLevel: json['floor_level'] as int?,
      devicesCount: json['devices_count'] as int? ?? 0,
      onlineDevices: json['online_devices'] as int? ?? 0,
      openAlertCount: json['open_alert_count'] as int? ?? 0,
      primaryDeviceId: json['primary_device_id']?.toString(),
      primaryDeviceStatus: json['primary_device_status']?.toString(),
      lastEventType: json['last_event_type']?.toString(),
      lastEventAt: json['last_event_at'] == null
          ? null
          : DateTime.tryParse(json['last_event_at'].toString()),
      status: (json['status'] ?? 'normal').toString(),
    );
  }

  String get locationLabel {
    final building = buildingCode ?? buildingName;
    if (building == null && floorLevel == null) {
      return zone;
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
