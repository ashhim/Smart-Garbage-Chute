class AlertViewData {
  const AlertViewData({
    required this.reasonCode,
    required this.reasonLabel,
    required this.severityLabel,
    required this.description,
    required this.title,
    required this.notificationBody,
    required this.roomLine,
    this.deviceLine,
    this.roomCode,
    this.roomName,
    this.deviceId,
  });

  factory AlertViewData.fromPayload(Map<String, dynamic> payload) {
    return AlertViewData.fromFields(
      category:
          payload['category']?.toString() ?? payload['event_type']?.toString(),
      severity: payload['severity']?.toString(),
      message: payload['message']?.toString(),
      title: payload['title']?.toString(),
      body: payload['body']?.toString(),
      roomCode: payload['room_code']?.toString(),
      roomName: payload['room_name']?.toString(),
      deviceId: payload['device_id']?.toString(),
    );
  }

  factory AlertViewData.fromFields({
    String? category,
    String? severity,
    String? message,
    String? title,
    String? body,
    String? roomCode,
    String? roomName,
    String? deviceId,
  }) {
    final resolvedReason = _resolveReason(
      category: category,
      message: message,
      title: title,
      body: body,
    );
    final resolvedSeverity = _resolveSeverity(
      severity: severity,
      title: title,
      body: body,
      message: message,
    );
    final resolvedRoomCode = _cleanText(roomCode);
    final resolvedRoomName = _cleanText(roomName);
    final resolvedDeviceId = _cleanText(deviceId);
    final resolvedDescription = resolvedReason.description ??
        _cleanText(message) ??
        _cleanText(body) ??
        _cleanText(title) ??
        'Alert detected in the chute room.';

    final titleTarget = resolvedRoomCode ?? resolvedRoomName ?? 'Facility';
    final roomLine = _buildRoomLine(
      roomCode: resolvedRoomCode,
      roomName: resolvedRoomName,
    );
    final deviceLine =
        resolvedDeviceId == null ? null : 'Device: $resolvedDeviceId';

    final bodyLines = <String>[
      resolvedDescription,
      roomLine,
      if (deviceLine != null) deviceLine,
    ];

    return AlertViewData(
      reasonCode: resolvedReason.code,
      reasonLabel: resolvedReason.label,
      severityLabel: resolvedSeverity,
      description: resolvedDescription,
      title: '[$resolvedSeverity] $titleTarget: ${resolvedReason.label}',
      notificationBody: bodyLines.join('\n'),
      roomLine: roomLine,
      deviceLine: deviceLine,
      roomCode: resolvedRoomCode,
      roomName: resolvedRoomName,
      deviceId: resolvedDeviceId,
    );
  }

  final String reasonCode;
  final String reasonLabel;
  final String severityLabel;
  final String description;
  final String title;
  final String notificationBody;
  final String roomLine;
  final String? deviceLine;
  final String? roomCode;
  final String? roomName;
  final String? deviceId;

  static const List<_AlertReasonTemplate> _reasonTemplates =
      <_AlertReasonTemplate>[
    _AlertReasonTemplate(
      code: 'LEAK',
      label: 'Leak',
      description: 'Liquid detected on the chute room floor.',
      aliases: <String>{'leak', 'leak detected', 'leakage', 'liquid'},
    ),
    _AlertReasonTemplate(
      code: 'BLOCKAGE',
      label: 'Blockage',
      description: 'Blockage pattern detected at chute inlet.',
      aliases: <String>{'blockage', 'blocked', 'obstruction'},
    ),
    _AlertReasonTemplate(
      code: 'OVERFLOW',
      label: 'Overflow',
      description: 'Overflow risk detected by controller and CCTV assist.',
      aliases: <String>{'overflow'},
    ),
    _AlertReasonTemplate(
      code: 'DOOR',
      label: 'Door',
      description: 'Door left open too long.',
      aliases: <String>{
        'door open',
        'door_open',
        'door prolonged open',
        'door_prolonged_open',
      },
    ),
    _AlertReasonTemplate(
      code: 'MISUSE',
      label: 'Misuse',
      description: 'Potential misuse detected in chute room.',
      aliases: <String>{
        'misuse',
        'ai misuse',
        'ai_misuse',
        'garbage left',
        'garbage_left',
        'garbage on floor',
        'garbage_on_floor',
        'person detected',
      },
    ),
    _AlertReasonTemplate(
      code: 'MOTION',
      label: 'Motion',
      description: 'Motion detected in chute room.',
      aliases: <String>{'motion', 'motion detected'},
    ),
  ];

  static _ResolvedReason _resolveReason({
    String? category,
    String? message,
    String? title,
    String? body,
  }) {
    final normalizedSearchSpace = _normalizeSearchSpace(
      <String?>[category, message, title, body],
    );
    for (final template in _reasonTemplates) {
      for (final alias in template.aliases) {
        if (normalizedSearchSpace.contains(_normalizeValue(alias))) {
          return _ResolvedReason(
            code: template.code,
            label: template.label,
            description: template.description,
          );
        }
      }
    }

    return const _ResolvedReason(
      code: 'ALERT',
      label: 'Alert',
      description: null,
    );
  }

  static String _normalizeSearchSpace(List<String?> values) {
    return values
        .map(_cleanText)
        .whereType<String>()
        .map(_normalizeValue)
        .join(' ');
  }

  static String _normalizeValue(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static String? _cleanText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String _normalizeSeverity(String? severity) {
    switch (_cleanText(severity)?.toLowerCase()) {
      case 'critical':
        return 'CRITICAL';
      case 'high':
        return 'HIGH';
      case 'medium':
        return 'MEDIUM';
      case 'low':
        return 'LOW';
      default:
        return 'INFO';
    }
  }

  static String _resolveSeverity({
    String? severity,
    String? title,
    String? body,
    String? message,
  }) {
    final normalizedSeverity = _normalizeSeverity(severity);
    if (normalizedSeverity != 'INFO' || _cleanText(severity) != null) {
      return normalizedSeverity;
    }

    final match = RegExp(
      r'\b(critical|high|medium|low|info)\b',
      caseSensitive: false,
    ).firstMatch(
      _normalizeSearchSpace(<String?>[title, body, message]),
    );
    return _normalizeSeverity(match?.group(1));
  }

  static String _buildRoomLine({
    required String? roomCode,
    required String? roomName,
  }) {
    if (roomName != null && roomCode != null) {
      return 'Room: $roomName ($roomCode)';
    }
    if (roomName != null) {
      return 'Room: $roomName';
    }
    if (roomCode != null) {
      return 'Room: $roomCode';
    }
    return 'Room: Unknown chute room';
  }
}

class _AlertReasonTemplate {
  const _AlertReasonTemplate({
    required this.code,
    required this.label,
    required this.description,
    required this.aliases,
  });

  final String code;
  final String label;
  final String description;
  final Set<String> aliases;
}

class _ResolvedReason {
  const _ResolvedReason({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String? description;
}
