import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();

  factory NotificationService() => instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  Timer? _sirenTimer;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  Future<void> showRealtimeAlert({
    required String title,
    required String body,
    String severity = 'info',
    bool playSiren = false,
  }) async {
    await initialize();

    final urgent = playSiren || _isUrgentSeverity(severity);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'smart-garbage-alerts',
        'Smart Garbage Alerts',
        channelDescription: 'Realtime chute room alerts and notifications',
        importance: urgent ? Importance.max : Importance.high,
        priority: urgent ? Priority.max : Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );

    if (urgent) {
      await playUrgentSiren();
    }
  }

  Future<void> playUrgentSiren() async {
    await initialize();

    _sirenTimer?.cancel();
    await _audioPlayer.stop();
    await _audioPlayer.setVolume(1);
    await _audioPlayer.play(AssetSource('alaram.mp3'));

    _sirenTimer = Timer(const Duration(seconds: 8), () {
      _audioPlayer.stop();
    });
  }

  Future<void> stopUrgentSiren() async {
    _sirenTimer?.cancel();
    await _audioPlayer.stop();
  }

  Future<String?> getToken() async {
    return null;
  }

  Future<void> subscribeToTopic(String topic) async {}

  Future<void> unsubscribeFromTopic(String topic) async {}

  bool _isUrgentSeverity(String severity) {
    final normalized = severity.toLowerCase();
    return normalized == 'high' || normalized == 'critical';
  }
}
