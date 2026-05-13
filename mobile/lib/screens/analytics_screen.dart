import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/ai_event.dart';
import '../models/maintenance_log.dart';
import '../models/ota_job.dart';
import '../services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<_OperationsData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchData();
  }

  Future<_OperationsData> _fetchData() async {
    final apiService = context.read<ApiService>();
    final summaryPayload = apiService.expectMap(
      await apiService.get('/analytics/summary'),
    );
    final aiPayload = apiService.expectList(
      await apiService.get('/ai-events?limit=12'),
    );
    final maintenancePayload = apiService.expectList(
      await apiService.get('/maintenance?limit=12'),
    );
    final otaPayload = apiService.expectList(
      await apiService.get('/ota/jobs'),
    );

    return _OperationsData(
      aiEvents24h: summaryPayload['ai_events_24h'] as int? ?? 0,
      otaJobsActive: summaryPayload['ota_jobs_active'] as int? ?? 0,
      alertsOpen: summaryPayload['alerts_open'] as int? ?? 0,
      aiEvents: aiPayload.map(AiEvent.fromJson).toList(),
      maintenanceLogs: maintenancePayload.map(MaintenanceLog.fromJson).toList(),
      otaJobs: otaPayload.map(OtaJob.fromJson).toList(),
      apiBaseUrl: apiService.apiBaseUrl,
      websocketUrl: apiService.websocketUrl,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _dataFuture = _fetchData();
    });
    await _dataFuture;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<_OperationsData>(
        future: _dataFuture,
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
                      Text('Failed to load operations data: ${snapshot.error}'),
                    ],
                  ),
                ),
              ],
            );
          }

          final data = snapshot.data!;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Operations',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _summaryChip('AI Events 24h', '${data.aiEvents24h}'),
                  _summaryChip('OTA Active', '${data.otaJobsActive}'),
                  _summaryChip('Open Alerts', '${data.alertsOpen}'),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI CCTV Events',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (data.aiEvents.isEmpty)
                        const Text('No AI events available.')
                      else
                        ...data.aiEvents.take(8).map(
                              (event) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.videocam_outlined),
                                title: Text(
                                    '${event.roomCode} • ${event.eventType}'),
                                subtitle: Text(
                                  'Confidence ${event.confidence.toStringAsFixed(2)} • ${timeago.format(event.createdAt)}',
                                ),
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
                        'OTA Jobs',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (data.otaJobs.isEmpty)
                        const Text('No OTA jobs found.')
                      else
                        ...data.otaJobs.map(
                          (job) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                const Icon(Icons.system_update_alt_outlined),
                            title: Text('${job.targetType} • ${job.targetRef}'),
                            subtitle: Text(
                              '${job.firmwareVersion} • ${job.status} • ${job.progress}%',
                            ),
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
                        'Maintenance Queue',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (data.maintenanceLogs.isEmpty)
                        const Text('No maintenance items recorded.')
                      else
                        ...data.maintenanceLogs.map(
                          (log) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.build_circle_outlined),
                            title: Text('Room ${log.roomId} • ${log.status}'),
                            subtitle: Text(
                              '${log.issue}\n${log.notes ?? ''}'.trim(),
                            ),
                            isThreeLine:
                                log.notes != null && log.notes!.isNotEmpty,
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
                        'Connectivity',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text('API: ${data.apiBaseUrl}'),
                      const SizedBox(height: 8),
                      Text('WebSocket: ${data.websocketUrl}'),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryChip(String label, String value) {
    return Chip(
      avatar: const Icon(Icons.insights_outlined, size: 18),
      label: Text('$label: $value'),
    );
  }
}

class _OperationsData {
  _OperationsData({
    required this.aiEvents24h,
    required this.otaJobsActive,
    required this.alertsOpen,
    required this.aiEvents,
    required this.maintenanceLogs,
    required this.otaJobs,
    required this.apiBaseUrl,
    required this.websocketUrl,
  });

  final int aiEvents24h;
  final int otaJobsActive;
  final int alertsOpen;
  final List<AiEvent> aiEvents;
  final List<MaintenanceLog> maintenanceLogs;
  final List<OtaJob> otaJobs;
  final String apiBaseUrl;
  final String websocketUrl;
}
