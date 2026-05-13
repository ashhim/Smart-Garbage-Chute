import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api_service.dart';

const String _backgroundAlertTask = 'smart_garbage_alert_sync';

@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.instance.handleBackgroundAlertSync();
    return true;
  });
}

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();
  static const _alertChannelId = 'smart-garbage-alerts';
  static const _lastNotifiedAlertIdKey = 'last_notified_alert_id';
  static const _tokenKey = 'auth_token';
  static const _apiBaseKey = ApiService.apiBaseStorageKey;

  factory NotificationService() => instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
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
    await Workmanager().initialize(
      notificationCallbackDispatcher,
      isInDebugMode: false,
    );

    const channel = AndroidNotificationChannel(
      _alertChannelId,
      'Smart Garbage Alerts',
      description: 'Realtime chute room alerts and notifications',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alaram'),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

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

  Future<void> configureBackgroundMonitoring({
    required String? token,
  }) async {
    await initialize();
    if (token == null || token.isEmpty) {
      await cancelBackgroundMonitoring();
      return;
    }

    await Workmanager().registerPeriodicTask(
      _backgroundAlertTask,
      _backgroundAlertTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      initialDelay: const Duration(minutes: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  Future<void> cancelBackgroundMonitoring() async {
    await Workmanager().cancelByUniqueName(_backgroundAlertTask);
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
        _alertChannelId,
        'Smart Garbage Alerts',
        channelDescription: 'Realtime chute room alerts and notifications',
        importance: urgent ? Importance.max : Importance.high,
        priority: urgent ? Priority.max : Priority.high,
        playSound: true,
        sound:
            urgent ? const RawResourceAndroidNotificationSound('alaram') : null,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
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

  Future<void> handleBackgroundAlertSync() async {
    try {
      await initialize();

      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) {
        return;
      }

      final apiBaseUrl =
          await _storage.read(key: _apiBaseKey) ?? _buildOverrideApiBaseUrl();
      if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
        return;
      }
      final response = await http.get(
        Uri.parse('${_normalizeApiBaseUrl(apiBaseUrl)}/alerts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastNotifiedAlertId = prefs.getInt(_lastNotifiedAlertIdKey) ?? 0;

      final urgentAlerts = decoded
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .where(
            (alert) =>
                (alert['acknowledged'] as bool? ?? false) == false &&
                _isUrgentSeverity((alert['severity'] ?? 'info').toString()) &&
                ((alert['id'] as num?)?.toInt() ?? 0) > lastNotifiedAlertId,
          )
          .toList()
        ..sort(
          (left, right) => ((left['id'] as num?)?.toInt() ?? 0)
              .compareTo(((right['id'] as num?)?.toInt() ?? 0)),
        );

      if (urgentAlerts.isEmpty) {
        return;
      }

      final newestAlert = urgentAlerts.last;
      final roomCode = newestAlert['room_code']?.toString();
      final body =
          newestAlert['message']?.toString() ?? 'Urgent chute room alert';
      await _plugin.show(
        (newestAlert['id'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        'Urgent ${roomCode ?? 'facility'} alert',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannelId,
            'Smart Garbage Alerts',
            channelDescription: 'Realtime chute room alerts and notifications',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('alaram'),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );

      await prefs.setInt(
        _lastNotifiedAlertIdKey,
        (newestAlert['id'] as num?)?.toInt() ?? lastNotifiedAlertId,
      );
    } catch (_) {
      return;
    }
  }

  Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  Future<void> subscribeToTopic(String topic) async {}

  Future<void> unsubscribeFromTopic(String topic) async {}

  static bool _isUrgentSeverity(String severity) {
    final normalized = severity.toLowerCase();
    return normalized == 'high' || normalized == 'critical';
  }

  static String _normalizeApiBaseUrl(String rawValue) {
    var value = rawValue.trim();
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('/api')) {
      return value;
    }
    if (value.contains('/api/')) {
      return value.replaceFirst(RegExp(r'/api/.+$'), '/api');
    }
    return '$value/api';
  }

  static String? _buildOverrideApiBaseUrl() {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.trim().isEmpty) {
      return null;
    }
    return _normalizeApiBaseUrl(defined);
  }
}
