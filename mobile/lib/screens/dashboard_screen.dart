import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/alert.dart';
import '../models/alert_view_data.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'alerts_screen.dart';
import 'analytics_screen.dart';
import 'devices_screen.dart';
import 'rooms_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const _fallbackRefreshInterval = Duration(seconds: 20);
  static const _defaultRefreshDebounce = Duration(milliseconds: 900);
  static const _heartbeatRefreshDebounce = Duration(seconds: 3);

  int _selectedIndex = 0;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _fallbackRefreshTimer;
  Timer? _wsReconnectTimer;
  Timer? _scheduledRefreshTimer;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  bool _isLoading = true;
  bool _simulationRunning = false;
  bool _simulationBusy = false;
  bool _isLiveRefreshInFlight = false;
  bool _hasPendingLiveRefresh = false;
  bool _isWebSocketConnected = false;
  int _tabRefreshToken = 0;
  int _webSocketReconnectAttempts = 0;

  int _totalBuildings = 0;
  int _totalRooms = 0;
  int _totalDevices = 0;
  int _activeAlerts = 0;
  int _aiEvents24h = 0;
  int _otaJobsActive = 0;

  String? _statusMessage;
  String? _selectedRoomCode;
  String _simulationEvent = 'blockage';

  List<Alert> _recentAlerts = const [];
  List<Room> _rooms = const [];
  final List<Map<String, dynamic>> _realtimeEvents = [];
  Map<String, dynamic>? _urgentEvent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.setAppLifecycleState(_appLifecycleState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        NotificationService.instance.ensureForegroundNotificationAccess(),
      );
    });
    _connectWebSocket();
    _startFallbackRefreshTimer();
    unawaited(_reloadLiveData(showLoading: true, broadcastToTabs: false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fallbackRefreshTimer?.cancel();
    _wsReconnectTimer?.cancel();
    _scheduledRefreshTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    NotificationService.instance.stopUrgentSiren();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isForegroundState(_appLifecycleState);
    final isForeground = _isForegroundState(state);

    _appLifecycleState = state;
    NotificationService.instance.setAppLifecycleState(state);

    if (!wasForeground && isForeground) {
      unawaited(
        NotificationService.instance.ensureForegroundNotificationAccess(),
      );
      _connectWebSocket(forceReconnect: true);
      _startFallbackRefreshTimer();
      _scheduleLiveRefresh(delay: Duration.zero);
      return;
    }

    if (wasForeground && !isForeground) {
      _fallbackRefreshTimer?.cancel();
      unawaited(
        NotificationService.instance.scheduleImmediateBackgroundSync(),
      );
    }
  }

  void _connectWebSocket({bool forceReconnect = false}) {
    if (!mounted) {
      return;
    }

    if (!forceReconnect && _isWebSocketConnected) {
      return;
    }

    _wsReconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();

    final apiService = context.read<ApiService>();
    try {
      _wsChannel = apiService.connectWebSocket();
      _wsSubscription = _wsChannel?.stream.listen(
        (message) {
          try {
            final payload = message is String
                ? jsonDecode(message) as Map<String, dynamic>
                : (message as Map).cast<String, dynamic>();
            _webSocketReconnectAttempts = 0;
            _isWebSocketConnected = true;
            _handleRealtimePayload(payload);
          } catch (error) {
            debugPrint('WebSocket parse error: $error');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _handleWebSocketDisconnect();
        },
        onDone: () {
          debugPrint('WebSocket closed');
          _handleWebSocketDisconnect();
        },
        cancelOnError: true,
      );
      _isWebSocketConnected = true;
      _webSocketReconnectAttempts = 0;
    } catch (error) {
      debugPrint('WebSocket connect error: $error');
      _handleWebSocketDisconnect();
    }
  }

  void _handleRealtimePayload(Map<String, dynamic> payload) {
    if (!mounted) {
      return;
    }

    final type = payload['type']?.toString() ?? 'event';
    final severity = _severityForPayload(payload);
    final urgent = _isUrgentSeverity(severity);

    setState(() {
      _realtimeEvents.insert(0, payload);
      if (_realtimeEvents.length > 12) {
        _realtimeEvents.removeRange(12, _realtimeEvents.length);
      }

      if (type == 'alert.created') {
        _activeAlerts += 1;
      } else if (type == 'alert.acknowledged') {
        _activeAlerts = max(0, _activeAlerts - 1);
      }

      if (urgent) {
        _urgentEvent = payload;
      }
    });

    if (_shouldRefreshForPayload(payload)) {
      _scheduleLiveRefresh(
        delay: _refreshDelayForPayload(payload),
      );
    }

    if (type == 'alert.created' || type == 'notification') {
      final alertViewData = AlertViewData.fromPayload(payload);
      final alertId = _extractAlertId(payload);

      unawaited(
        NotificationService.instance.showRealtimeAlert(
          title: alertViewData.title,
          body: alertViewData.notificationBody,
          severity: severity,
          playSiren: urgent,
          alertId: alertId,
          showSystemNotification: urgent,
        ),
      );

      if (_isForegroundState(_appLifecycleState)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: urgent ? Colors.red.shade700 : null,
            content: Text(alertViewData.notificationBody),
          ),
        );
      }
    }
  }

  void _handleWebSocketDisconnect() {
    _isWebSocketConnected = false;

    if (!mounted || _wsReconnectTimer?.isActive == true) {
      return;
    }

    _webSocketReconnectAttempts += 1;
    final retryDelaySeconds = min(30, 2 * _webSocketReconnectAttempts);
    _wsReconnectTimer = Timer(
      Duration(seconds: retryDelaySeconds),
      () => _connectWebSocket(forceReconnect: true),
    );

    if (!_isForegroundState(_appLifecycleState)) {
      unawaited(
        NotificationService.instance.scheduleImmediateBackgroundSync(
          initialDelay: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _startFallbackRefreshTimer() {
    _fallbackRefreshTimer?.cancel();
    if (!_isForegroundState(_appLifecycleState)) {
      return;
    }

    _fallbackRefreshTimer = Timer.periodic(
      _fallbackRefreshInterval,
      (_) => _scheduleLiveRefresh(delay: Duration.zero),
    );
  }

  void _scheduleLiveRefresh({
    Duration delay = _defaultRefreshDebounce,
  }) {
    if (!mounted) {
      return;
    }

    if (delay == Duration.zero) {
      unawaited(_reloadLiveData());
      return;
    }

    _scheduledRefreshTimer?.cancel();
    _scheduledRefreshTimer = Timer(delay, () {
      unawaited(_reloadLiveData());
    });
  }

  Future<void> _reloadLiveData({
    bool showLoading = false,
    bool broadcastToTabs = true,
  }) async {
    if (_isLiveRefreshInFlight) {
      _hasPendingLiveRefresh = true;
      return;
    }

    _isLiveRefreshInFlight = true;
    try {
      await _loadDashboardData(
        showLoading: showLoading,
        broadcastToTabs: broadcastToTabs,
      );
    } finally {
      _isLiveRefreshInFlight = false;
      if (_hasPendingLiveRefresh && mounted) {
        _hasPendingLiveRefresh = false;
        unawaited(_reloadLiveData());
      }
    }
  }

  Future<void> _loadDashboardData({
    bool showLoading = false,
    bool broadcastToTabs = false,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final apiService = context.read<ApiService>();
      final responses = await Future.wait<dynamic>([
        apiService.get('/analytics/summary'),
        apiService.get('/rooms'),
        apiService.get('/alerts'),
      ]);
      final summaryPayload = apiService.expectMap(responses[0]);
      final roomPayload = apiService.expectList(responses[1]);
      final alertPayload = apiService.expectList(responses[2]);

      if (!mounted) {
        return;
      }

      setState(() {
        _totalBuildings = summaryPayload['buildings'] as int? ?? 0;
        _totalRooms = summaryPayload['rooms'] as int? ?? 0;
        _totalDevices = summaryPayload['devices'] as int? ?? 0;
        _activeAlerts = summaryPayload['alerts_open'] as int? ?? 0;
        _aiEvents24h = summaryPayload['ai_events_24h'] as int? ?? 0;
        _otaJobsActive = summaryPayload['ota_jobs_active'] as int? ?? 0;
        _rooms = roomPayload.map(Room.fromJson).toList();
        _recentAlerts = alertPayload.take(5).map(Alert.fromJson).toList();
        _selectedRoomCode ??=
            _rooms.isNotEmpty ? _rooms.first.roomCode : 'CHR_01';
        if (broadcastToTabs) {
          _tabRefreshToken += 1;
        }
        _isLoading = false;
        _statusMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to load dashboard data: $error';
      });
    }
  }

  Future<void> _callSimulation(String path,
      [Map<String, dynamic>? body]) async {
    setState(() {
      _simulationBusy = true;
      _statusMessage = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final payload = await apiService.post(path, body);
      final response =
          payload == null ? <String, dynamic>{} : apiService.expectMap(payload);

      if (!mounted) {
        return;
      }

      setState(() {
        if (path == '/simulation/start' && response['ok'] == true) {
          _simulationRunning = true;
        }
        if (path == '/simulation/stop' && response['ok'] == true) {
          _simulationRunning = false;
        }
        _statusMessage =
            response['message']?.toString() ?? 'Simulation request completed.';
      });

      await _reloadLiveData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Simulation error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _simulationBusy = false;
        });
      }
    }
  }

  Future<void> _dismissUrgentBanner() async {
    await NotificationService.instance.stopUrgentSiren();
    if (!mounted) {
      return;
    }
    setState(() {
      _urgentEvent = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Garbage Chute'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await NotificationService.instance.stopUrgentSiren();
                await authService.logout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                value: 'role',
                child: Text(currentUser?.roleLabel ?? 'Authenticated User'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildOverviewTab(currentUser),
          RoomsScreen(refreshToken: _tabRefreshToken),
          AlertsScreen(refreshToken: _tabRefreshToken),
          DevicesScreen(refreshToken: _tabRefreshToken),
          AnalyticsScreen(refreshToken: _tabRefreshToken),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Overview',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.meeting_room_outlined),
            label: 'Rooms',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_rounded),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.memory_outlined),
            label: 'Devices',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: 'Ops',
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(AppUser? currentUser) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _reloadLiveData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_urgentEvent != null) ...[
            _buildUrgentBanner(),
            const SizedBox(height: 16),
          ],
          _buildUserBanner(currentUser),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildStatCard(
                'Buildings',
                _totalBuildings.toString(),
                Icons.apartment_outlined,
                Colors.blue,
              ),
              _buildStatCard(
                'Rooms',
                _totalRooms.toString(),
                Icons.meeting_room_outlined,
                Colors.teal,
              ),
              _buildStatCard(
                'Devices',
                _totalDevices.toString(),
                Icons.devices_other_outlined,
                Colors.orange,
              ),
              _buildStatCard(
                'Open Alerts',
                _activeAlerts.toString(),
                Icons.warning_amber_rounded,
                Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sensors_outlined),
                      const SizedBox(width: 8),
                      Text(
                        'Realtime Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('AI Events 24h: $_aiEvents24h')),
                      Chip(label: Text('OTA Active: $_otaJobsActive')),
                      Chip(
                        label: Text(
                          _simulationRunning
                              ? 'Simulation running'
                              : 'Simulation idle',
                        ),
                      ),
                    ],
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (currentUser?.canUseSimulation ?? false) ...[
            const SizedBox(height: 16),
            _buildSimulationCard(),
          ],
          const SizedBox(height: 16),
          _buildRecentAlertsCard(),
          const SizedBox(height: 16),
          _buildRealtimeFeedCard(),
        ],
      ),
    );
  }

  Widget _buildUrgentBanner() {
    final alertViewData = AlertViewData.fromPayload(
      _urgentEvent ?? const <String, dynamic>{},
    );

    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alertViewData.title,
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _dismissUrgentBanner,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              alertViewData.description,
              style: TextStyle(color: Colors.red.shade900),
            ),
            const SizedBox(height: 6),
            Text(
              alertViewData.roomLine,
              style: TextStyle(color: Colors.red.shade800),
            ),
            if (alertViewData.deviceLine != null) ...[
              const SizedBox(height: 6),
              Text(
                alertViewData.deviceLine!,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUserBanner(AppUser? currentUser) {
    final apiService = context.watch<ApiService>();
    final name = currentUser?.fullName.isNotEmpty == true
        ? currentUser!.fullName
        : currentUser?.email ?? 'Authenticated user';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Signed in as $name',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(currentUser?.roleLabel ?? 'Viewer')),
                Chip(label: Text('Server: ${apiService.serverDisplayName}')),
                Chip(label: Text(apiService.useHttps ? 'HTTPS' : 'HTTP')),
                if (currentUser?.readOnly ?? false)
                  const Chip(label: Text('Read-only access')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Simulation Controls',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRoomCode,
              items: _rooms
                  .map(
                    (room) => DropdownMenuItem<String>(
                      value: room.roomCode,
                      child: Text('${room.roomCode} - ${room.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedRoomCode = value);
              },
              decoration: const InputDecoration(
                labelText: 'Room',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _simulationEvent,
              items: const [
                'heartbeat',
                'door_open',
                'door_prolonged_open',
                'blockage',
                'overflow',
                'leak',
                'motion',
                'garbage_left',
                'misuse',
              ]
                  .map(
                    (event) => DropdownMenuItem<String>(
                      value: event,
                      child: Text(event.replaceAll('_', ' ')),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _simulationEvent = value);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Event Type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _simulationBusy
                      ? null
                      : () => _callSimulation('/simulation/start'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start'),
                ),
                OutlinedButton.icon(
                  onPressed: _simulationBusy
                      ? null
                      : () => _callSimulation('/simulation/stop'),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _simulationBusy || _selectedRoomCode == null
                      ? null
                      : () => _callSimulation(
                            '/simulation/emit',
                            {
                              'room_code': _selectedRoomCode,
                              'event_type': _simulationEvent,
                              'severity':
                                  _simulationSeverityFor(_simulationEvent),
                            },
                          ),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Inject Event'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentAlertsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Alerts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_recentAlerts.isEmpty)
              const Text('No recent alerts.')
            else
              ..._recentAlerts.map(
                (alert) {
                  final alertViewData = alert.viewData;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      alert.severityIcon,
                      color: alert.severityColor,
                    ),
                    title: Text(alertViewData.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alertViewData.description),
                        Text(alertViewData.roomLine),
                        if (alertViewData.deviceLine != null)
                          Text(alertViewData.deviceLine!),
                        Text(
                          timeago.format(alert.createdAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: alert.acknowledged
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : Text(alert.severity.toUpperCase()),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeFeedCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Realtime Feed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_realtimeEvents.isEmpty)
              const Text('Waiting for websocket events...')
            else
              ..._realtimeEvents.map(
                (event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    (event['type'] ?? event['event_type'] ?? 'event')
                        .toString()
                        .replaceAll('_', ' '),
                  ),
                  subtitle: Text(
                    jsonEncode(event),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  String _simulationSeverityFor(String eventType) {
    switch (eventType) {
      case 'heartbeat':
      case 'motion':
        return 'info';
      case 'door_open':
        return 'medium';
      case 'door_prolonged_open':
      case 'blockage':
      case 'overflow':
      case 'leak':
      case 'garbage_left':
      case 'misuse':
        return 'high';
      default:
        return 'medium';
    }
  }

  bool _shouldRefreshForPayload(Map<String, dynamic> payload) {
    final type = payload['type']?.toString().toLowerCase() ?? 'event';
    final eventType = payload['event_type']?.toString().toLowerCase() ?? '';

    if (type == 'telemetry' ||
        type == 'ai_event' ||
        type == 'alert.created' ||
        type == 'alert.acknowledged' ||
        type == 'notification') {
      return true;
    }

    return switch (eventType) {
      'heartbeat' ||
      'door_open' ||
      'door_prolonged_open' ||
      'blockage' ||
      'overflow' ||
      'leak' ||
      'motion' ||
      'misuse' ||
      'garbage_left' ||
      'garbage_on_floor' ||
      'ai_misuse' =>
        true,
      _ => false,
    };
  }

  Duration _refreshDelayForPayload(Map<String, dynamic> payload) {
    final eventType = payload['event_type']?.toString().toLowerCase();
    if (eventType == 'heartbeat') {
      return _heartbeatRefreshDebounce;
    }
    return _defaultRefreshDebounce;
  }

  int? _extractAlertId(Map<String, dynamic> payload) {
    return int.tryParse(
      payload['alert_id']?.toString() ?? payload['id']?.toString() ?? '',
    );
  }

  String _severityForPayload(Map<String, dynamic> payload) {
    final severity = payload['severity']?.toString().trim().toLowerCase();
    if (severity != null && severity.isNotEmpty) {
      return severity;
    }

    final title = payload['title']?.toString() ?? '';
    final match = RegExp(
      r'^\[(critical|high|medium|low|info)\]',
      caseSensitive: false,
    ).firstMatch(title);
    return match?.group(1)?.toLowerCase() ?? 'info';
  }

  bool _isUrgentSeverity(String severity) {
    return severity == 'high' || severity == 'critical';
  }

  bool _isForegroundState(AppLifecycleState state) {
    return state == AppLifecycleState.resumed;
  }
}
