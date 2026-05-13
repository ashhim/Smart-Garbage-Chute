import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/room.dart';
import '../services/api_service.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  late Future<List<Room>> _roomsFuture;

  @override
  void initState() {
    super.initState();
    _roomsFuture = _fetchRooms();
  }

  Future<List<Room>> _fetchRooms() async {
    final apiService = context.read<ApiService>();
    final payload = await apiService.get('/rooms');
    return apiService.expectList(payload).map(Room.fromJson).toList();
  }

  Future<void> _reload() async {
    setState(() {
      _roomsFuture = _fetchRooms();
    });
    await _roomsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<Room>>(
        future: _roomsFuture,
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
                      Text('Failed to load rooms: ${snapshot.error}'),
                    ],
                  ),
                ),
              ],
            );
          }

          final rooms = snapshot.data ?? const [];
          if (rooms.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No rooms detected')),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        _statusColor(room.status).withValues(alpha: 0.12),
                    child: Icon(
                      Icons.meeting_room_outlined,
                      color: _statusColor(room.status),
                    ),
                  ),
                  title: Text('${room.roomCode} - ${room.name}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room.locationLabel),
                      const SizedBox(height: 4),
                      Text(
                        'Devices ${room.onlineDevices}/${room.devicesCount} | Alerts ${room.openAlertCount}',
                      ),
                      Text(
                        room.lastEventAt == null
                            ? 'Last event: --'
                            : 'Last event: ${room.lastEventType ?? '--'} | ${timeago.format(room.lastEventAt!)}',
                      ),
                    ],
                  ),
                  trailing: Chip(
                    label: Text(room.status),
                    backgroundColor:
                        _statusColor(room.status).withValues(alpha: 0.12),
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'attention':
        return Colors.orange;
      case 'offline':
        return Colors.red;
      case 'active':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }
}
