import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/alert.dart';
import '../models/device.dart';
import '../models/room.dart';
import 'alerts_screen.dart';
import 'devices_screen.dart';
import 'analytics_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  WebSocketChannel? _wsChannel;

  late List<Alert> _recentAlerts = [];
  late int _totalBuildings = 0;
  late int _totalRooms = 0;
  late int _totalDevices = 0;
  late int _activeAlerts = 0;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _loadDashboardData();
  }

  void _connectWebSocket() {
    final apiService = context.read<ApiService>();
    _wsChannel = apiService.connectWebSocket();

    _wsChannel?.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          _handleWebSocketMessage(data);
        } catch (e) {
          debugPrint('WebSocket error: $e');
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

  void _handleWebSocketMessage(Map<String, dynamic> data) {
    if (!mounted) return;

    final type = data['type'];
    if (type == 'alert') {
      setState(() {
        _activeAlerts++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New Alert: ${data['message']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final apiService = context.read<ApiService>();
      final summary = await apiService.get('/analytics/summary');

      setState(() {
        _totalBuildings = summary['buildings'] ?? 0;
        _totalRooms = summary['rooms'] ?? 0;
        _totalDevices = summary['devices'] ?? 0;
        _activeAlerts = summary['alerts_open'] ?? 0;
      });

      // Load recent alerts
      final alertsData = await apiService.get('/alerts?limit=5');
      setState(() {
        _recentAlerts =
            (alertsData['items'] as List)
                .map((a) => Alert.fromJson(a))
                .toList();
      });
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
    }
  }

  @override
  void dispose() {
    _wsChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Garbage Chute'),
        actions: [
          Consumer<AuthService>(
            builder: (context, authService, _) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: PopupMenuButton(
                  itemBuilder:
                      (context) => [
                        PopupMenuItem(
                          child: const Text('Profile'),
                          onTap: () {},
                        ),
                        PopupMenuItem(
                          child: const Text('Settings'),
                          onTap: () {},
                        ),
                        PopupMenuItem(
                          child: const Text('Logout'),
                          onTap: () {
                            authService.logout();
                          },
                        ),
                      ],
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildOverviewTab(),
          const AlertsScreen(),
          const DevicesScreen(),
          _buildAnalyticsTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'Devices'),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Grid
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStatCard(
                  'Buildings',
                  _totalBuildings.toString(),
                  Icons.apartment,
                  Colors.blue,
                ),
                _buildStatCard(
                  'Rooms',
                  _totalRooms.toString(),
                  Icons.room,
                  Colors.green,
                ),
                _buildStatCard(
                  'Devices',
                  _totalDevices.toString(),
                  Icons.devices,
                  Colors.orange,
                ),
                _buildStatCard(
                  'Alerts',
                  _activeAlerts.toString(),
                  Icons.warning,
                  Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Recent Alerts
            Text(
              'Recent Alerts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_recentAlerts.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No recent alerts',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ListView.builder(
                itemCount: _recentAlerts.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final alert = _recentAlerts[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(
                        alert.getSeverityIcon(),
                        color: alert.getSeverityColor(),
                      ),
                      title: Text(alert.message),
                      subtitle: Text('Room ${alert.roomId}'),
                      trailing:
                          alert.acknowledged
                              ? const Icon(Icons.check, color: Colors.green)
                              : const Text('New'),
                    ),
                  );
                },
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
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return Center(
      child: Text(
        'Analytics Dashboard',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: true,
            onChanged: (value) {},
          ),
          SwitchListTile(
            title: const Text('Alert Sounds'),
            value: true,
            onChanged: (value) {},
          ),
        ],
      ),
    );
  }
}
