import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/alert.dart';
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

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;

  bool _isLoading = true;
  bool _simulationRunning = false;
  bool _simulationBusy = false;

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

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    unawaited(_loadDashboardData());
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  void _connectWebSocket() {
    final apiService = context.read<ApiService>();
    _wsChannel = apiService.connectWebSocket();
    _wsSubscription = _wsChannel?.stream.listen(
      (message) {
        try {
          final payload = message is String
              ? jsonDecode(message) as Map<String, dynamic>
              : (message as Map).cast<String, dynamic>();
          _handleRealtimePayload(payload);
        } catch (error) {
          debugPrint('WebSocket parse error: $error');
        }
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
      },
      onDone: () {
        debugPrint('WebSocket closed');
      },
    );
  }

  void _handleRealtimePayload(Map<String, dynamic> payload) {
    if (!mounted) {
      return;
    }

    final type = payload['type']?.toString() ?? 'event';
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
    });

    if (type == 'alert.created' || type == 'notification') {
      final title = type == 'notification'
          ? (payload['title']?.toString() ?? 'Control room notification')
          : 'New alert';
      final body = payload['message']?.toString() ??
          payload['body']?.toString() ??
          'Realtime event received';

      NotificationService.instance.showRealtimeAlert(
        title: title,
        body: body,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(body)),
      );
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final apiService = context.read<ApiService>();
      final summaryPayload = apiService.expectMap(
        await apiService.get('/analytics/summary'),
      );
      final roomPayload = apiService.expectList(await apiService.get('/rooms'));
      final alertPayload =
          apiService.expectList(await apiService.get('/alerts'));

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
        _isLoading = false;
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

      await _loadDashboardData();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Garbage Chute'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await context.read<AuthService>().logout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
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
          _buildOverviewTab(),
          const RoomsScreen(),
          const AlertsScreen(),
          const DevicesScreen(),
          const AnalyticsScreen(),
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

  Widget _buildOverviewTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
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
                                    'severity': _simulationSeverityFor(
                                      _simulationEvent,
                                    ),
                                  },
                                ),
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Inject Event'),
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
          const SizedBox(height: 16),
          Card(
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
                      (alert) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          alert.severityIcon,
                          color: alert.severityColor,
                        ),
                        title: Text(alert.message),
                        subtitle: Text(
                          '${alert.roomLabel} • ${timeago.format(alert.createdAt)}',
                        ),
                        trailing: alert.acknowledged
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : Text(alert.severity.toUpperCase()),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
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
          ),
        ],
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
}
