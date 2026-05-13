import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/alert.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({Key? key}) : super(key: key);

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late Future<List<Alert>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() {
    final apiService = context.read<ApiService>();
    _alertsFuture = _fetchAlerts(apiService);
  }

  Future<List<Alert>> _fetchAlerts(ApiService apiService) async {
    try {
      final data = await apiService.get('/alerts?limit=100');
      final alerts =
          (data['items'] as List?)?.map((a) => Alert.fromJson(a)).toList() ??
          [];
      return alerts;
    } catch (e) {
      debugPrint('Error loading alerts: $e');
      rethrow;
    }
  }

  Future<void> _acknowledgeAlert(int alertId) async {
    try {
      final apiService = context.read<ApiService>();
      await apiService.post('/alerts/$alertId/acknowledge', {});
      _loadAlerts();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Alert acknowledged')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: (_) async => setState(() => _loadAlerts()),
      child: FutureBuilder<List<Alert>>(
        future: _alertsFuture,
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

          final alerts = snapshot.data ?? [];

          if (alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text('No alerts'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: alerts.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(
                    alert.getSeverityIcon(),
                    color: alert.getSeverityColor(),
                    size: 32,
                  ),
                  title: Text(alert.message),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Room ${alert.roomId} • ${alert.category}'),
                      Text(
                        _formatTime(alert.createdAt),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  trailing:
                      alert.acknowledged
                          ? const Icon(Icons.check, color: Colors.green)
                          : IconButton(
                            icon: const Icon(Icons.done),
                            onPressed: () => _acknowledgeAlert(alert.id),
                          ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
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
