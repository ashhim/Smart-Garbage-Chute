import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  late FlutterLocalNotificationsPlugin _localNotifications;

  Future<void> initialize() async {
    // Initialize Firebase (if credentials provided)
    try {
      await Firebase.initializeApp();
    } catch (e) {
      print('Firebase not configured: $e');
    }

    // Initialize local notifications
    _localNotifications = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iOSSettings =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(android: androidSettings, iOS: iOSSettings);

    await _localNotifications.initialize(initializationSettings);

    // Request permissions
    await _firebaseMessaging.requestPermission();

    // Listen to foreground notifications
    FirebaseMessaging.onMessage.listen(_handleForegroundNotification);

    // Listen to notification tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }

  Future<void> _handleForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    print('Notification tapped: ${message.messageId}');
    // Navigate to alert details screen
  }

  Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }

  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
  }
}
