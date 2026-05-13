import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/alert.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late Future<List<Alert>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _alertsFuture = _fetchAlerts();
  }

  Future<List<Alert>> _fetchAlerts() async {
    final apiService = context.read<ApiService>();
    final payload = await apiService.get('/alerts');
    return apiService
        .expectList(payload)
        .take(100)
        .map(Alert.fromJson)
        .toList();
  }

  Future<void> _reload() async {
    setState(() {
      _alertsFuture = _fetchAlerts();
    });
    await _alertsFuture;
  }

  Future<void> _acknowledgeAlert(int alertId) async {
    try {
      final apiService = context.read<ApiService>();
      await apiService.post('/alerts/$alertId/acknowledge', {
        'actor': 'mobile-app',
      });
      await _reload();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert acknowledged')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Acknowledge failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAcknowledge = context.watch<AuthService>().canAcknowledgeAlerts;

    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<Alert>>(
        future: _alertsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
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
                      Text('Failed to load alerts: ${snapshot.error}'),
                    ],
                  ),
                ),
              ],
            );
          }

          final alerts = snapshot.data ?? const [];
          if (alerts.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No alerts')),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(
                    alert.severityIcon,
                    color: alert.severityColor,
                    size: 30,
                  ),
                  title: Text(alert.message),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${alert.roomLabel} | ${alert.category}'),
                      Text(
                        '${alert.source} | ${timeago.format(alert.createdAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: alert.acknowledged
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : canAcknowledge
                          ? IconButton(
                              icon: const Icon(Icons.done_outline),
                              onPressed: () => _acknowledgeAlert(alert.id),
                            )
                          : const Icon(Icons.remove_red_eye_outlined),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
