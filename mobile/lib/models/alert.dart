import 'package:flutter/material.dart';

class Alert {
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

  Alert({
    required this.id,
    required this.roomId,
    required this.source,
    required this.category,
    required this.message,
    required this.severity,
    required this.acknowledged,
    this.acknowledgedBy,
    this.acknowledgedAt,
    required this.createdAt,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'],
      roomId: json['room_id'],
      source: json['source'],
      category: json['category'],
      message: json['message'],
      severity: json['severity'],
      acknowledged: json['acknowledged'],
      acknowledgedBy: json['acknowledged_by'],
      acknowledgedAt:
          json['acknowledged_at'] != null
              ? DateTime.parse(json['acknowledged_at'])
              : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Color getSeverityColor() {
    switch (severity.toLowerCase()) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF0066CC);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData getSeverityIcon() {
    switch (severity.toLowerCase()) {
      case 'high':
        return Icons.warning;
      case 'medium':
        return Icons.notifications;
      case 'low':
        return Icons.info;
      default:
        return Icons.help;
    }
  }
}
