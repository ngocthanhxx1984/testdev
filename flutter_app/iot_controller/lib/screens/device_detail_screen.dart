import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../models/device.dart';
import '../models/room.dart';

class DeviceDetailScreen extends StatelessWidget {
  final String deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, provider, _) {
        final device = provider.devices
            .cast<IoTDevice?>()
            .firstWhere((d) => d?.id == deviceId, orElse: () => null);

        if (device == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Device')),
            body: const Center(child: Text('Device not found')),
          );
        }

        final isOnline = device.status == DeviceStatus.online;
        final room = getRoomByName(device.room);

        return Scaffold(
          appBar: AppBar(
            title: Text(device.id),
            actions: [
              // Room assignment
              IconButton(
                icon: Icon(room.icon, color: room.color),
                tooltip: 'Change room',
                onPressed: () => _showRoomPicker(context, device),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Status header
              _StatusHeader(device: device),
              const SizedBox(height: 20),

              // Device info
              _InfoCard(device: device),
              const SizedBox(height: 16),

              // Sensor readings (AHT10)
              if (device.hasTemperature || device.hasHumidity) ...[
                _SensorCard(device: device),
                const SizedBox(height: 16),
              ],

              // Motion status (PIR)
              if (device.hasMotion) ...[
                _MotionCard(device: device),
                const SizedBox(height: 16),
              ],

              // Controls (relay, LED, etc.)
              ...device.features
                  .where((f) =>
                      f != 'temperature' &&
                      f != 'humidity' &&
                      f != 'motion')
                  .map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ControlCard(
                          device: device,
                          feature: feature,
                          isOnline: isOnline,
                        ),
                      )),
            ],
          ),
        );
      },
    );
  }

  void _showRoomPicker(BuildContext context, IoTDevice device) {
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Status Header ────────────────────────────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  final IoTDevice device;
  const _StatusHeader({required this.device});

  @override
  Widget build(BuildContext context) {
    final isOnline = device.status == DeviceStatus.online;
    final theme = Theme.of(context);
    final room = getRoomByName(device.room);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOnline
              ? [theme.colorScheme.primaryContainer, theme.colorScheme.surface]
              : [Colors.grey[300]!, Colors.grey[100]!],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isOnline
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _getDeviceIcon(),
              size: 36,
              color: isOnline ? theme.colorScheme.primary : Colors.grey[400],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.id,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(device.typeLabel,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(room.icon, size: 14, color: room.color),
                    const SizedBox(width: 4),
                    Text(device.room,
                        style: TextStyle(fontSize: 12, color: room.color)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isOnline
                  ? Colors.green.withOpacity(0.15)
                  : Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              device.statusText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isOnline ? Colors.green[700] : Colors.red[700],
              ),
            ),
          ),
        ],
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
}

// ── Info Card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IoTDevice device;
  const _InfoCard({required this.device});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Device Info',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _infoRow('Type', device.type),
            _infoRow('Firmware', 'v${device.firmwareVersion}'),
            _infoRow('Features', device.features.join(', ')),
            if (device.rssi != null)
              _infoRow('RSSI', '${device.rssi} dBm'),
            if (device.uptime != null)
              _infoRow('Uptime', _formatUptime(device.uptime!)),
            _infoRow('Last Seen', _formatTime(device.lastSeen)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _formatUptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

// ── Sensor Card (AHT10) ─────────────────────────────────────────────────────

class _SensorCard extends StatelessWidget {
  final IoTDevice device;
  const _SensorCard({required this.device});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sensor Readings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (device.hasTemperature)
                  Expanded(
                    child: _SensorGauge(
                      icon: Icons.thermostat,
                      label: 'Temperature',
                      value: device.temperature != null
                          ? '${device.temperature!.toStringAsFixed(1)}°C'
                          : '--',
                      color: Colors.red,
                    ),
                  ),
                if (device.hasTemperature && device.hasHumidity)
                  const SizedBox(width: 16),
                if (device.hasHumidity)
                  Expanded(
                    child: _SensorGauge(
                      icon: Icons.water_drop,
                      label: 'Humidity',
                      value: device.humidity != null
                          ? '${device.humidity!.toStringAsFixed(1)}%'
                          : '--',
                      color: Colors.blue,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorGauge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SensorGauge(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

// ── Motion Card (PIR) ───────────────────────────────────────────────────────

class _MotionCard extends StatelessWidget {
  final IoTDevice device;
  const _MotionCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final motionCount = device.featureStates['motion_count'];
    final isMotion = device.motionDetected;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isMotion ? Colors.red[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Motion Sensor',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isMotion
                        ? Colors.red.withOpacity(0.2)
                        : Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMotion
                            ? Icons.directions_run
                            : Icons.check_circle_outline,
                        size: 16,
                        color: isMotion ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isMotion ? 'Motion Detected!' : 'Clear',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isMotion ? Colors.red : Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (motionCount != null) ...[
              const SizedBox(height: 12),
              Text('Total motion events: $motionCount',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Control Card (relay, LED, etc.) ─────────────────────────────────────────

class _ControlCard extends StatelessWidget {
  final IoTDevice device;
  final String feature;
  final bool isOnline;
  const _ControlCard(
      {required this.device, required this.feature, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final isOn = device.featureStates[feature] == true;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isOn
                    ? Colors.amber.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _getFeatureIcon(),
                size: 28,
                color: isOn ? Colors.amber[700] : Colors.grey[400],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(feature.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(isOn ? 'ON' : 'OFF',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isOn ? Colors.amber[700] : Colors.grey,
                      )),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.3,
              child: Switch(
                value: isOn,
                onChanged: isOnline
                    ? (val) => context
                        .read<DeviceProvider>()
                        .sendCommand(device.id, feature, val)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFeatureIcon() {
    switch (feature) {
      case 'relay':
        return Icons.electrical_services;
      case 'led':
        return Icons.lightbulb_outline;
      default:
        return Icons.toggle_on;
    }
  }
}
