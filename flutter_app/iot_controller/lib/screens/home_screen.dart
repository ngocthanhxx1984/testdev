import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../providers/mqtt_provider.dart';
import '../models/device.dart';
import '../models/room.dart';
import 'device_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<DeviceProvider, MqttProvider>(
      builder: (context, deviceProvider, mqttProvider, child) {
        if (!mqttProvider.isConnected && deviceProvider.devices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Not connected to MQTT broker',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('Go to Settings to configure your HiveMQ connection',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    textAlign: TextAlign.center),
              ],
            ),
          );
        }

        if (deviceProvider.devices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices_other, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No devices discovered yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('Waiting for ESP8266 devices to broadcast...',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ],
            ),
          );
        }

        final byRoom = deviceProvider.devicesByRoom;
        final roomNames = deviceProvider.rooms;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: roomNames.length,
          itemBuilder: (context, index) {
            final roomName = roomNames[index];
            final roomDevices = byRoom[roomName] ?? [];
            final room = getRoomByName(roomName);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Row(
                    children: [
                      Icon(room.icon, size: 18, color: room.color),
                      const SizedBox(width: 8),
                      Text(roomName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: room.color)),
                      const Spacer(),
                      Text('${roomDevices.length}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                ...roomDevices.map((device) =>
                    _DeviceListTile(device: device)),
              ],
            );
          },
        );
      },
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  final IoTDevice device;
  const _DeviceListTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final isOnline = device.status == DeviceStatus.online;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: isOnline ? 2 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DeviceDetailScreen(deviceId: device.id),
            ),
          );
        },
        onLongPress: () => _showRoomPicker(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Device icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isOnline
                      ? theme.colorScheme.primaryContainer
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getDeviceIcon(),
                  size: 24,
                  color: isOnline
                      ? theme.colorScheme.primary
                      : Colors.grey[400],
                ),
              ),
              const SizedBox(width: 12),

              // Name + type
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.id,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(device.typeLabel,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ),

              // RSSI
              if (device.rssi != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getRssiIcon(device.rssi!),
                        size: 16,
                        color: _getRssiColor(device.rssi!),
                      ),
                      const SizedBox(width: 2),
                      Text('${device.rssi}',
                          style: TextStyle(
                              fontSize: 11,
                              color: _getRssiColor(device.rssi!))),
                    ],
                  ),
                ),

              // Online/Offline badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline
                      ? Colors.green.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  device.statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isOnline ? Colors.green[700] : Colors.red[700],
                  ),
                ),
              ),

              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getDeviceIcon() {
    switch (device.type) {
      case 'esp8266_aht10':
        return Icons.thermostat;
      case 'esp8266_pir':
        return Icons.sensors;
      default:
        return Icons.developer_board;
    }
  }

  IconData _getRssiIcon(int rssi) {
    if (rssi > -50) return Icons.signal_wifi_4_bar;
    if (rssi > -60) return Icons.network_wifi_3_bar;
    if (rssi > -70) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  Color _getRssiColor(int rssi) {
    if (rssi > -50) return Colors.green;
    if (rssi > -60) return Colors.lightGreen;
    if (rssi > -70) return Colors.orange;
    return Colors.red;
  }

  void _showRoomPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assign "${device.id}" to room',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: defaultRooms.map((room) {
                final isSelected = device.room == room.name;
                return ChoiceChip(
                  avatar: Icon(room.icon, size: 18),
                  label: Text(room.name),
                  selected: isSelected,
                  onSelected: (_) {
                    context
                        .read<DeviceProvider>()
                        .assignRoom(device.id, room.name);
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
            const Divider(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmDeleteDevice(context);
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Delete Device',
                    style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteDevice(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text(
            'Remove "${device.id}" from your device list?\n\n'
            'It will reappear if it broadcasts discovery again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<DeviceProvider>().removeDevice(device.id);
              Navigator.pop(ctx);
            },
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
