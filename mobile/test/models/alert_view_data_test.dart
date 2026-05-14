import 'package:flutter_test/flutter_test.dart';
import 'package:smart_garbage_mobile/models/alert_view_data.dart';

void main() {
  test('maps leak alerts to room-aware notification content', () {
    final alertViewData = AlertViewData.fromFields(
      category: 'leak',
      severity: 'high',
      roomCode: 'CHR_01',
      roomName: 'Chute Room 01',
      deviceId: 'ESP32-01',
    );

    expect(alertViewData.reasonCode, 'LEAK');
    expect(alertViewData.title, '[HIGH] CHR_01: Leak');
    expect(
      alertViewData.notificationBody,
      'Liquid detected on the chute room floor.\n'
      'Room: Chute Room 01 (CHR_01)\n'
      'Device: ESP32-01',
    );
  });

  test('maps door alerts to the structured DOOR reason', () {
    final alertViewData = AlertViewData.fromFields(
      category: 'door_open',
      severity: 'critical',
      roomCode: 'CHR_22',
    );

    expect(alertViewData.reasonCode, 'DOOR');
    expect(alertViewData.title, '[CRITICAL] CHR_22: Door');
    expect(alertViewData.description, 'Door left open too long.');
  });

  test('infers reason mapping from notification titles when category is absent',
      () {
    final alertViewData = AlertViewData.fromPayload(
      <String, dynamic>{
        'title': '[HIGH] CHR_03: Blockage',
        'body': 'Unexpected generic body',
        'room_code': 'CHR_03',
      },
    );

    expect(alertViewData.reasonCode, 'BLOCKAGE');
    expect(alertViewData.title, '[HIGH] CHR_03: Blockage');
    expect(
      alertViewData.description,
      'Blockage pattern detected at chute inlet.',
    );
  });
}
