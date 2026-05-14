import 'package:flutter/material.dart';

import 'alert_view_data.dart';

class Alert {
  Alert({
    required this.id,
    required this.roomId,
    required this.source,
    required this.category,
    required this.message,
    required this.severity,
    required this.acknowledged,
    required this.createdAt,
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.roomCode,
    this.roomName,
    this.buildingCode,
    this.buildingName,
    this.deviceId,
  });

  final int id;
  final int roomId;
  final String source;
  final String category;
  final String message;
  final String severity;
  final bool acknowledged;
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;
  final String? roomCode;
  final String? roomName;
  final String? buildingCode;
  final String? buildingName;
  final String? deviceId;

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as int,
      roomId: json['room_id'] as int,
      source: (json['source'] ?? 'system').toString(),
      category: (json['category'] ?? 'alert').toString(),
      message: (json['message'] ?? 'No message provided').toString(),
      severity: (json['severity'] ?? 'medium').toString(),
      acknowledged: json['acknowledged'] as bool? ?? false,
      acknowledgedBy: json['acknowledged_by']?.toString(),
      acknowledgedAt: json['acknowledged_at'] == null
          ? null
          : DateTime.tryParse(json['acknowledged_at'].toString()),
      createdAt: DateTime.parse(json['created_at'].toString()),
      roomCode: json['room_code']?.toString(),
      roomName: json['room_name']?.toString(),
      buildingCode: json['building_code']?.toString(),
      buildingName: json['building_name']?.toString(),
      deviceId: json['device_id']?.toString(),
    );
  }

  String get roomLabel {
    final code = roomCode ?? 'Room $roomId';
    if (roomName == null || roomName!.isEmpty) {
      return code;
    }
    return '$code - $roomName';
  }

  AlertViewData get viewData => AlertViewData.fromFields(
        category: category,
        severity: severity,
        message: message,
        roomCode: roomCode,
        roomName: roomName,
        deviceId: deviceId,
      );

  Color get severityColor {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFB91C1C);
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF0284C7);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData get severityIcon {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'high':
        return Icons.warning_rounded;
      case 'medium':
        return Icons.notification_important_outlined;
      case 'low':
        return Icons.info_outline;
      default:
        return Icons.notifications_none;
    }
  }
}
