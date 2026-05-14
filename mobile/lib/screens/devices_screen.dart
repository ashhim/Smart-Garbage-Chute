import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/device.dart';
import '../services/api_service.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({
    super.key,
    required this.refreshToken,
  });

  final int refreshToken;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<Device>> _devicesFuture;

  @override
  void initState() {
    super.initState();
    _devicesFuture = _fetchDevices();
  }

  @override
  void didUpdateWidget(covariant DevicesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      _reload();
    }
  }

  Future<List<Device>> _fetchDevices() async {
    final apiService = context.read<ApiService>();
    final payload = await apiService.get('/devices');
    return apiService.expectList(payload).map(Device.fromJson).toList();
  }

  Future<void> _reload() async {
    setState(() {
      _devicesFuture = _fetchDevices();
    });
    await _devicesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<Device>>(
        future: _devicesFuture,
        builder: (context, snapshot) {
          final devices = snapshot.data ?? const <Device>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              devices.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Failed to load devices: ${snapshot.error}'),
                    ],
                  ),
                ),
              ],
            );
          }

          if (devices.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No devices discovered')),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: devices.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: device.online
                        ? Colors.green.shade50
                        : Colors.grey.shade200,
                    child: Icon(
                      Icons.memory_outlined,
                      color: device.online ? Colors.green : Colors.grey,
                    ),
                  ),
                  title: Text(device.deviceId),
                  subtitle: Text(
                    '${device.roomLabel} | ${device.online ? 'Online' : 'Offline'}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _detailRow('Location', device.locationLabel),
                    _detailRow('Type', device.deviceType),
                    _detailRow('Firmware', device.firmwareVersion),
                    _detailRow('Open Alerts', '${device.openAlertCount}'),
                    _detailRow(
                      'Last Seen',
                      device.lastSeenAt == null
                          ? 'Never'
                          : timeago.format(device.lastSeenAt!),
                    ),
                    _detailRow(
                      'Last Event',
                      device.lastEventType == null
                          ? '--'
                          : '${device.lastEventType} | ${device.lastEventAt == null ? '--' : timeago.format(device.lastEventAt!)}',
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
