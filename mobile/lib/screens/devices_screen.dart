import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/device.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({Key? key}) : super(key: key);

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<Device>> _devicesFuture;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() {
    final apiService = context.read<ApiService>();
    _devicesFuture = _fetchDevices(apiService);
  }

  Future<List<Device>> _fetchDevices(ApiService apiService) async {
    try {
      final data = await apiService.get('/devices');
      final devices =
          (data['items'] as List?)?.map((d) => Device.fromJson(d)).toList() ??
          [];
      return devices;
    } catch (e) {
      debugPrint('Error loading devices: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: (_) async => setState(() => _loadDevices()),
      child: FutureBuilder<List<Device>>(
        future: _devicesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final devices = snapshot.data ?? [];

          if (devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.devices_other,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text('No devices'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: devices.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: Icon(
                    Icons.router,
                    color: device.online ? Colors.green : Colors.grey,
                  ),
                  title: Text(device.deviceId),
                  subtitle: Text(
                    'Room ${device.roomId} • ${device.online ? 'Online' : 'Offline'}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Device ID', device.deviceId),
                          _buildDetailRow('Type', device.deviceType),
                          _buildDetailRow('Firmware', device.firmwareVersion),
                          _buildDetailRow(
                            'Last Seen',
                            device.lastSeenAt != null
                                ? _formatDateTime(device.lastSeenAt!)
                                : 'Never',
                          ),
                        ],
                      ),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
