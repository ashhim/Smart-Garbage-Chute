import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/alert_view_data.dart';
import 'api_service.dart';

const String _backgroundAlertTask = 'smart_garbage_alert_sync';
const String _backgroundBootstrapTask = 'smart_garbage_alert_sync_bootstrap';
const String _backgroundImmediateTask = 'smart_garbage_alert_sync_immediate';

@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return NotificationService.instance.handleBackgroundAlertSync();
  });
}

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();
  static const _alertChannelId = 'smart-garbage-alerts-general-v2';
  static const _criticalAlertChannelId = 'smart-garbage-alerts-critical-v2';
  static const _alertChannelName = 'Smart Garbage Alerts';
  static const _criticalAlertChannelName = 'Smart Garbage Critical Alerts';
  static const _alertChannelDescription =
      'Realtime chute room alerts and notifications';
  static const _criticalAlertChannelDescription =
      'Critical chute room alerts that require immediate attention';
  static const _alarmSound = RawResourceAndroidNotificationSound('alaram');
  static const _backgroundTokenKey = 'background_alert_auth_token';
  static const _backgroundApiBaseUrlKey = 'background_alert_api_base_url';
  static const _lastNotifiedAlertIdKey = 'last_notified_alert_id';
  static const _notificationChannelVersionKey =
      'notification_channel_schema_version';
  static const _notificationChannelVersion = 3;
  static const _tokenKey = 'auth_token';
  static const _apiBaseKey = ApiService.apiBaseStorageKey;
  static const _duplicateNotificationWindow = Duration(seconds: 12);
  static const _legacyChannelIds = <String>[
    'smart-garbage-alerts',
    'smart-garbage-alerts-general',
    'smart-garbage-alerts-critical',
  ];

  factory NotificationService() => instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, DateTime> _recentNotificationKeys = <String, DateTime>{};

  Timer? _sirenTimer;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _notificationsInitialized = false;
  bool _backgroundWorkerInitialized = false;
  DateTime? _lastNotificationPermissionRequestAt;

  Future<void> initialize({
    bool requestPermissions = false,
  }) async {
    await _ensureNotificationsInitialized(
      requestPermissions: requestPermissions,
    );
    await _ensureBackgroundWorkerInitialized();
  }

  Future<bool> ensureForegroundNotificationAccess() async {
    await initialize(requestPermissions: false);
    return _ensureNotificationAccess(requestIfNeeded: true);
  }

  Future<void> _ensureNotificationsInitialized({
    required bool requestPermissions,
  }) async {
    if (_notificationsInitialized) {
      if (requestPermissions) {
        await _requestPermissions();
      }
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(settings);
    await _createNotificationChannels();
    await _configureAudioPlayer();

    _notificationsInitialized = true;

    if (requestPermissions) {
      await _requestPermissions();
    }
  }

  Future<void> _ensureBackgroundWorkerInitialized() async {
    if (_backgroundWorkerInitialized || !_supportsBackgroundAlertSync) {
      return;
    }

    await Workmanager().initialize(
      notificationCallbackDispatcher,
      isInDebugMode: false,
    );
    _backgroundWorkerInitialized = true;
  }

  Future<void> _createNotificationChannels() async {
    final androidImplementation = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_notificationChannelVersionKey) ?? 0;
    if (storedVersion != _notificationChannelVersion) {
      for (final channelId in <String>{
        ..._legacyChannelIds,
        _alertChannelId,
        _criticalAlertChannelId,
      }) {
        await androidImplementation.deleteNotificationChannel(channelId);
      }
    }

    const defaultChannel = AndroidNotificationChannel(
      _alertChannelId,
      _alertChannelName,
      description: _alertChannelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Android 8+ binds the sound to the channel the first time it is created.
    const criticalChannel = AndroidNotificationChannel(
      _criticalAlertChannelId,
      _criticalAlertChannelName,
      description: _criticalAlertChannelDescription,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: _alarmSound,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    await androidImplementation.createNotificationChannel(defaultChannel);
    await androidImplementation.createNotificationChannel(criticalChannel);

    if (storedVersion != _notificationChannelVersion) {
      await prefs.setInt(
        _notificationChannelVersionKey,
        _notificationChannelVersion,
      );
    }
  }

  Future<void> _requestPermissions() async {
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
  }

  Future<void> _configureAudioPlayer() async {
    await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
        ),
      ),
    );
  }

  Future<void> configureBackgroundMonitoring({
    required String? token,
  }) async {
    if (!_supportsBackgroundAlertSync) {
      return;
    }

    await initialize(requestPermissions: false);
    await _storeBackgroundAccess(token);
    if (token == null || token.isEmpty) {
      await cancelBackgroundMonitoring();
      return;
    }

    final constraints = Constraints(
      networkType: NetworkType.connected,
    );

    await Workmanager().registerOneOffTask(
      _backgroundBootstrapTask,
      _backgroundAlertTask,
      initialDelay: const Duration(seconds: 10),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: constraints,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
      outOfQuotaPolicy: _expeditedPolicyForDelay(
        const Duration(seconds: 10),
      ),
    );

    await Workmanager().registerPeriodicTask(
      _backgroundAlertTask,
      _backgroundAlertTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      initialDelay: const Duration(minutes: 15),
      constraints: constraints,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  Future<void> scheduleImmediateBackgroundSync({
    Duration initialDelay = const Duration(seconds: 15),
  }) async {
    if (!_supportsBackgroundAlertSync) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_backgroundTokenKey);
    if (token == null || token.isEmpty) {
      return;
    }

    await _ensureBackgroundWorkerInitialized();

    await Workmanager().registerOneOffTask(
      _backgroundImmediateTask,
      _backgroundAlertTask,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      initialDelay: initialDelay,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
      outOfQuotaPolicy: _expeditedPolicyForDelay(initialDelay),
    );
  }

  Future<void> cancelBackgroundMonitoring() async {
    if (!_supportsBackgroundAlertSync) {
      return;
    }

    await _clearBackgroundAccess();
    await Workmanager().cancelByUniqueName(_backgroundImmediateTask);
    await Workmanager().cancelByUniqueName(_backgroundBootstrapTask);
    await Workmanager().cancelByUniqueName(_backgroundAlertTask);
  }

  Future<void> showRealtimeAlert({
    required String title,
    required String body,
    String severity = 'info',
    bool playSiren = false,
    int? alertId,
    bool showSystemNotification = false,
  }) async {
    await _ensureNotificationsInitialized(requestPermissions: false);

    final urgent = playSiren || _isUrgentSeverity(severity);
    final notificationId =
        alertId ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final notificationKey = _buildNotificationKey(
      alertId: alertId,
      title: title,
      body: body,
      urgent: urgent,
    );
    final shouldShowSystemNotification =
        showSystemNotification || !_isAppInForeground;
    final isDuplicateNotification = shouldShowSystemNotification &&
        _isDuplicateNotification(notificationKey);
    var notificationPosted = false;

    if (shouldShowSystemNotification && !isDuplicateNotification) {
      final canPostNotifications = await _ensureNotificationAccess(
        requestIfNeeded: _isAppInForeground,
      );
      if (canPostNotifications) {
        notificationPosted = await _showAlertNotification(
          notificationId: notificationId,
          title: title,
          body: body,
          urgent: urgent,
        );
      }
    }

    final notificationHandledBySystem = shouldShowSystemNotification &&
        (isDuplicateNotification || notificationPosted);

    if (urgent && alertId != null && notificationHandledBySystem) {
      await _storeLastNotifiedAlertId(alertId);
    }

    if (urgent && _isAppInForeground) {
      await playUrgentSiren();
    }
  }

  Future<void> playUrgentSiren() async {
    await _ensureNotificationsInitialized(requestPermissions: false);

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

  Future<bool> handleBackgroundAlertSync() async {
    try {
      await _ensureNotificationsInitialized(requestPermissions: false);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_backgroundTokenKey) ??
          await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) {
        return true;
      }

      final apiBaseUrl = prefs.getString(_backgroundApiBaseUrlKey) ??
          await _storage.read(key: _apiBaseKey) ??
          _buildOverrideApiBaseUrl();
      if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
        return true;
      }
      final response = await http.get(
        Uri.parse('${_normalizeApiBaseUrl(apiBaseUrl)}/alerts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return false;
      }

      final lastNotifiedAlertId = prefs.getInt(_lastNotifiedAlertIdKey) ?? 0;

      final urgentAlerts = decoded
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .where(
            (alert) =>
                !_isAcknowledged(alert['acknowledged']) &&
                _isUrgentSeverity((alert['severity'] ?? 'info').toString()) &&
                (_parseAlertId(alert['id']) ?? 0) > lastNotifiedAlertId,
          )
          .toList()
        ..sort(
          (left, right) => (_parseAlertId(left['id']) ?? 0)
              .compareTo(_parseAlertId(right['id']) ?? 0),
        );

      if (urgentAlerts.isEmpty) {
        return true;
      }

      var newestAlertId = lastNotifiedAlertId;
      for (final urgentAlert in urgentAlerts) {
        final alertId = _parseAlertId(urgentAlert['id']) ??
            DateTime.now().millisecondsSinceEpoch;
        final alertViewData = AlertViewData.fromPayload(urgentAlert);

        await _showAlertNotification(
          notificationId: alertId,
          title: alertViewData.title,
          body: alertViewData.notificationBody,
          urgent: true,
        );

        if (alertId > newestAlertId) {
          newestAlertId = alertId;
        }
      }

      await prefs.setInt(_lastNotifiedAlertIdKey, newestAlertId);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Background alert sync error: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  Future<void> subscribeToTopic(String topic) async {}

  Future<void> unsubscribeFromTopic(String topic) async {}

  void setAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  bool get _supportsBackgroundAlertSync => Platform.isAndroid;
  bool get _isAppInForeground =>
      _appLifecycleState == AppLifecycleState.resumed;

  static bool _isUrgentSeverity(String severity) {
    final normalized = severity.toLowerCase();
    return normalized == 'high' || normalized == 'critical';
  }

  static bool _isAcknowledged(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  static int? _parseAlertId(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  Future<bool> _ensureNotificationAccess({
    required bool requestIfNeeded,
  }) async {
    if (Platform.isAndroid) {
      final androidImplementation =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation == null) {
        return true;
      }

      final notificationsEnabled =
          await androidImplementation.areNotificationsEnabled();
      if (notificationsEnabled ?? true) {
        return true;
      }

      if (!requestIfNeeded || !_isAppInForeground) {
        return false;
      }

      final now = DateTime.now();
      if (_lastNotificationPermissionRequestAt != null &&
          now.difference(_lastNotificationPermissionRequestAt!) <
              const Duration(seconds: 30)) {
        return false;
      }
      _lastNotificationPermissionRequestAt = now;

      return await androidImplementation.requestNotificationsPermission() ??
          false;
    }

    await _requestPermissions();
    return true;
  }

  Future<bool> _showAlertNotification({
    required int notificationId,
    required String title,
    required String body,
    required bool urgent,
  }) async {
    final channelId = urgent ? _criticalAlertChannelId : _alertChannelId;
    final channelName = urgent ? _criticalAlertChannelName : _alertChannelName;
    final channelDescription =
        urgent ? _criticalAlertChannelDescription : _alertChannelDescription;

    try {
      await _plugin.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: urgent ? Importance.max : Importance.high,
            priority: urgent ? Priority.max : Priority.high,
            styleInformation: BigTextStyleInformation(body),
            category: urgent ? AndroidNotificationCategory.alarm : null,
            visibility: NotificationVisibility.public,
            playSound: true,
            sound: urgent ? _alarmSound : null,
            ticker: title,
            enableLights: urgent,
            channelShowBadge: true,
            audioAttributesUsage: urgent
                ? AudioAttributesUsage.alarm
                : AudioAttributesUsage.notification,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('Notification post error: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> _storeLastNotifiedAlertId(int alertId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentValue = prefs.getInt(_lastNotifiedAlertIdKey) ?? 0;
    if (alertId > currentValue) {
      await prefs.setInt(_lastNotifiedAlertIdKey, alertId);
    }
  }

  Future<void> _storeBackgroundAccess(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_backgroundTokenKey);
      await prefs.remove(_backgroundApiBaseUrlKey);
      return;
    }

    await prefs.setString(_backgroundTokenKey, token);

    final apiBaseUrl =
        await _storage.read(key: _apiBaseKey) ?? _buildOverrideApiBaseUrl();
    if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
      await prefs.remove(_backgroundApiBaseUrlKey);
      return;
    }

    await prefs.setString(
      _backgroundApiBaseUrlKey,
      _normalizeApiBaseUrl(apiBaseUrl),
    );
  }

  Future<void> _clearBackgroundAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_backgroundTokenKey);
    await prefs.remove(_backgroundApiBaseUrlKey);
  }

  bool _isDuplicateNotification(String key) {
    final now = DateTime.now();
    _recentNotificationKeys.removeWhere(
      (_, timestamp) =>
          now.difference(timestamp) > _duplicateNotificationWindow,
    );

    final lastTimestamp = _recentNotificationKeys[key];
    if (lastTimestamp != null &&
        now.difference(lastTimestamp) <= _duplicateNotificationWindow) {
      return true;
    }

    _recentNotificationKeys[key] = now;
    return false;
  }

  String _buildNotificationKey({
    required int? alertId,
    required String title,
    required String body,
    required bool urgent,
  }) {
    if (alertId != null) {
      return 'alert:$alertId';
    }
    return '${urgent ? 'urgent' : 'normal'}|$title|$body';
  }

  OutOfQuotaPolicy? _expeditedPolicyForDelay(Duration initialDelay) {
    // Android rejects expedited work requests when any initial delay is applied.
    if (initialDelay > Duration.zero) {
      return null;
    }
    return OutOfQuotaPolicy.run_as_non_expedited_work_request;
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
