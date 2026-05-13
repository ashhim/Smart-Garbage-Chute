# Smart Garbage Chute - Mobile App Documentation

## Overview

The Flutter mobile application provides real-time monitoring and control of smart garbage chute systems across multiple buildings and rooms. The app integrates with the backend API via REST/WebSocket for real-time updates and notifications.

## Architecture

### Technology Stack

- **Framework**: Flutter 3.4+
- **UI Framework**: Material Design 3
- **State Management**: Provider + Riverpod
- **HTTP Client**: dio + http
- **Real-time**: WebSocket (web_socket_channel)
- **Notifications**: Firebase Cloud Messaging + Flutter Local Notifications
- **Storage**: Flutter Secure Storage + Shared Preferences
- **Platform**: iOS 12.0+ | Android API 21+

### Project Structure

```
mobile/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── screens/
│   │   ├── login_screen.dart        # Authentication
│   │   ├── dashboard_screen.dart    # Main dashboard
│   │   ├── alerts_screen.dart       # Alert management
│   │   ├── devices_screen.dart      # Device inventory
│   │   └── analytics_screen.dart    # Analytics
│   ├── services/
│   │   ├── auth_service.dart        # Auth & token management
│   │   ├── api_service.dart         # REST API client
│   │   └── notification_service.dart # FCM & local notifications
│   └── models/
│       ├── alert.dart               # Alert data model
│       ├── device.dart              # Device data model
│       └── room.dart                # Room data model
├── android/                         # Android platform code
├── ios/                             # iOS platform code
├── pubspec.yaml                     # Dependencies
└── test/                            # Unit & widget tests
```

## Features

### 1. Authentication

**Login Flow:**
- Email/password authentication
- JWT token storage (secure)
- Token refresh mechanism
- Automatic logout on 401

**Implementation:**
```dart
// Login
final success = await authService.login(email, password);

// Token management
apiService.setToken(authService.token!);

// Logout
await authService.logout();
```

### 2. Real-time Dashboard

**Overview Tab:**
- System statistics (buildings, rooms, devices, alerts)
- Recent alerts list
- Quick status indicators
- Auto-refresh (5s intervals)

**WebSocket Connection:**
```dart
_wsChannel = apiService.connectWebSocket();
_wsChannel?.stream.listen((message) {
  final data = jsonDecode(message);
  _handleWebSocketMessage(data);
});
```

**Message Types:**
- `telemetry`: Sensor readings
- `alert`: New alert notifications
- `ota`: Firmware update status

### 3. Alerts Management

**Alerts Screen:**
- Full alert list with pagination
- Severity-based color coding (red/yellow/blue)
- Acknowledgment workflow
- Time-relative display (e.g., "5m ago")

**Alert Acknowledgment:**
```dart
await apiService.post('/alerts/$alertId/acknowledge', {});
```

### 4. Device Monitoring

**Devices Screen:**
- Device inventory by room
- Online/offline status
- Firmware version tracking
- Last seen timestamp
- Expandable detail view

### 5. Analytics

**Analytics Tab:**
- Alerts by severity (24h)
- Top alert categories
- Trend visualization
- Historical comparisons

### 6. Push Notifications

**FCM Integration:**
- High priority alerts trigger notifications
- Sound and vibration alerts
- Foreground/background handling
- Tap-to-open navigation

**Setup:**
```dart
final fcmToken = await notificationService.getToken();
await apiService.post('/notifications/register-device', {
  'fcm_token': fcmToken,
  'platform': Platform.isAndroid ? 'android' : 'ios',
});
```

## API Integration

### Authentication Endpoints

```dart
// Login
POST /auth/login
{
  "email": "admin@alghurair.local",
  "password": "password123"
}
→ { "access_token": "...", "token_type": "bearer" }

// Token refresh
POST /auth/refresh
→ { "access_token": "..." }
```

### Data Endpoints

```dart
// Dashboard summary
GET /analytics/summary
→ {
  "buildings": 5,
  "rooms": 42,
  "devices": 50,
  "alerts_open": 8,
  ...
}

// Alerts list
GET /alerts?limit=50&offset=0
→ {
  "items": [
    {
      "id": 1,
      "room_id": 5,
      "severity": "high",
      "message": "Blockage detected",
      "acknowledged": false,
      "created_at": "2024-01-15T10:30:00Z"
    },
    ...
  ],
  "total": 125
}

// Devices list
GET /devices
→ {
  "items": [
    {
      "id": 1,
      "room_id": 5,
      "device_id": "ESP32_CHR_01",
      "firmware_version": "1.2.1",
      "online": true,
      "last_seen_at": "2024-01-15T10:35:00Z"
    },
    ...
  ]
}

// Alert acknowledgment
POST /alerts/{id}/acknowledge
→ { "acknowledged": true, "acknowledged_at": "..." }
```

### WebSocket

**Connection:**
```
ws://[host]/ws?token=[jwt_token]
```

**Message Format:**
```json
{
  "type": "alert|telemetry|ota",
  "data": {
    "id": 123,
    "room_id": 5,
    "message": "...",
    ...
  }
}
```

## Development Setup

### Prerequisites

```bash
# Flutter SDK 3.4+
flutter --version

# Android SDK (for Android development)
flutter doctor

# CocoaPods (for iOS development)
sudo gem install cocoapods
```

### Installation

```bash
# Clone repository
git clone https://github.com/alghurair/smart-garbage-chute-system.git
cd smart-garbage-chute-system/mobile

# Install dependencies
flutter pub get

# (iOS only) Install pod dependencies
cd ios && pod install && cd ..

# Run app
flutter run

# Or run on specific device
flutter run -d <device-id>
```

### Configuration

**Update API endpoints in `lib/services/api_service.dart`:**

```dart
static const String baseUrl = 'https://garbage-chute.yourdomain.com';
static const String wsUrl = 'wss://garbage-chute.yourdomain.com/ws';
```

## Firebase Setup

### Android

1. Create Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add Android app with package name `com.alghurair.smart_garbage_mobile`
3. Download `google-services.json` → `android/app/`
4. Configure Android build:

```gradle
// android/build.gradle
classpath 'com.google.gms:google-services:4.3.15'

// android/app/build.gradle
apply plugin: 'com.google.gms.google-services'
```

### iOS

1. Add iOS app in Firebase console
2. Download `GoogleService-Info.plist` → `ios/Runner/`
3. Configure in Xcode:
   - Target Runner → Build Phases → Copy Bundle Resources
   - Add `GoogleService-Info.plist`

## Building for Production

### Android

```bash
# Build APK
flutter build apk --release

# Build App Bundle (for Google Play)
flutter build appbundle --release

# Output: build/app/outputs/
```

### iOS

```bash
# Build for iOS
flutter build ios --release

# Archive in Xcode
open ios/Runner.xcworkspace
# Product → Archive

# Or use command line
flutter build ipa
```

## Testing

### Unit Tests

```bash
flutter test test/unit/

# Specific test file
flutter test test/unit/auth_service_test.dart
```

### Widget Tests

```bash
flutter test test/widget/

# Run all tests
flutter test
```

### Integration Tests

```bash
flutter test integration_test/
```

## Deployment

### Google Play Store

1. Create Play Store project
2. Configure signing:
   ```bash
   keytool -genkey -v -keystore android/key.jks -alias garbage_chute -keyalg RSA -keysize 2048 -validity 10000
   ```
3. Configure signing in `android/app/build.gradle`
4. Build app bundle: `flutter build appbundle`
5. Upload to Play Console

### Apple App Store

1. Create App Store Connect account
2. Create app bundle identifier: `com.alghurair.smartGarbageMobile`
3. Create provisioning profiles in Apple Developer
4. Build IPA: `flutter build ipa`
5. Upload via Xcode or Transporter app

## Monitoring & Analytics

### Crash Reporting

Add Sentry integration (optional):

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

await SentryFlutter.init(
  (options) => options.dsn = 'https://your-key@sentry.io/project',
  appRunner: () => runApp(const SmartGarbageApp()),
);
```

### User Analytics

```dart
// Track events
FirebaseAnalytics.instance.logEvent(
  name: 'alert_acknowledged',
  parameters: {'alert_id': alertId},
);
```

## Troubleshooting

### Common Issues

**WebSocket connection fails:**
- Check backend is running
- Verify API URL in api_service.dart
- Check token validity

**FCM notifications not received:**
- Verify device token registered
- Check Firebase configuration
- Enable notifications in app settings

**Login fails:**
- Verify credentials
- Check backend connectivity
- Review auth token expiration

## Security Best Practices

1. **Secure Token Storage:**
   - Always use `FlutterSecureStorage` for tokens
   - Never log tokens
   - Rotate tokens regularly

2. **HTTPS Only:**
   - Always use HTTPS in production
   - Validate SSL certificates
   - Don't disable certificate validation

3. **Input Validation:**
   - Validate all user inputs
   - Sanitize API responses
   - Use Pydantic models for API contracts

4. **Permissions:**
   - Request only necessary permissions
   - Handle permission denials gracefully
   - Document permission usage

## Performance Optimization

1. **Image Caching:**
```dart
ImageCache().maximumSize = 100;
ImageCache().maximumSizeBytes = 100 * 1024 * 1024; // 100MB
```

2. **List Virtualization:**
```dart
ListView.builder( // Instead of ListView
  itemCount: items.length,
  itemBuilder: (context, index) => ItemTile(items[index]),
)
```

3. **Network Optimization:**
- Use pagination (limit=50)
- Implement exponential backoff for retries
- Cache API responses with SWR pattern

## References

- [Flutter Documentation](https://flutter.dev/docs)
- [Firebase for Flutter](https://firebase.flutter.dev/)
- [Provider Package](https://pub.dev/packages/provider)
- [Dio HTTP Client](https://pub.dev/packages/dio)

## Support

For issues and feature requests, create an issue on [GitHub Issues](https://github.com/alghurair/smart-garbage-chute-system/issues).
