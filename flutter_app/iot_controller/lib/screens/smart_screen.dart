import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../providers/mqtt_provider.dart';
import '../models/device.dart';

class SmartScreen extends StatelessWidget {
  const SmartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<DeviceProvider, MqttProvider>(
      builder: (context, deviceProvider, mqttProvider, child) {
        if (!mqttProvider.isConnected) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Not connected to MQTT',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Go to Settings to configure and connect',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        final allDevices = deviceProvider.devices;

        if (allDevices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No devices discovered yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Waiting for devices to come online...',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: allDevices.length,
          itemBuilder: (context, index) {
            return _EntityCard(device: allDevices[index]);
          },
        );
      },
    );
  }
}

class _EntityCard extends StatelessWidget {
  final IoTDevice device;

  const _EntityCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final isOnline = device.status == DeviceStatus.online;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: isOnline ? 2 : 0.5,
      child: Opacity(
        opacity: isOnline ? 1.0 : 0.5,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device header
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isOnline
                        ? colorScheme.primaryContainer
                        : Colors.grey[300],
                    child: Icon(
                      _iconForType(device.type),
                      color: isOnline
                          ? colorScheme.primary
                          : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.id,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${device.typeLabel}  |  ${device.room}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isOnline ? Colors.green : Colors.red,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      device.statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isOnline ? Colors.green[800] : Colors.red[800],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              // Feature list
              ...device.features.map(
                (feature) => _FeatureRow(device: device, feature: feature),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'esp8266':
        return Icons.developer_board;
      case 'esp8266_aht10':
        return Icons.thermostat;
      case 'esp8266_pir':
        return Icons.sensors;
      default:
        return Icons.memory;
    }
  }
}

class _FeatureRow extends StatelessWidget {
  final IoTDevice device;
  final String feature;

  const _FeatureRow({required this.device, required this.feature});

  @override
  Widget build(BuildContext context) {
    final deviceProvider = context.read<DeviceProvider>();
    final isOnline = device.status == DeviceStatus.online;
    final state = device.featureStates[feature];

    // Sensor readings (read-only)
    if (feature == 'temperature') {
      final val = state is num ? state.toStringAsFixed(1) : '--';
      return _buildSensorRow(
        icon: Icons.thermostat,
        label: 'Temperature',
        value: '$val \u00B0C',
        color: Colors.orange,
      );
    }
    if (feature == 'humidity') {
      final val = state is num ? state.toStringAsFixed(1) : '--';
      return _buildSensorRow(
        icon: Icons.water_drop,
        label: 'Humidity',
        value: '$val %',
        color: Colors.blue,
      );
    }
    if (feature == 'motion') {
      final detected = state == true;
      return _buildSensorRow(
        icon: Icons.directions_run,
        label: 'Motion',
        value: detected ? 'Detected' : 'Clear',
        color: detected ? Colors.red : Colors.green,
      );
    }
    if (feature == 'motion_count') {
      final count = state is num ? state.toInt() : 0;
      return _buildSensorRow(
        icon: Icons.tag,
        label: 'Motion Count',
        value: '$count',
        color: Colors.purple,
      );
    }

    // Controllable features (relay, led) - toggleable
    final isOn = state == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            feature == 'relay' ? Icons.power : Icons.lightbulb_outline,
            size: 20,
            color: isOn ? Colors.amber[700] : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _featureLabel(feature),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Switch(
            value: isOn,
            onChanged: isOnline
                ? (val) {
                    deviceProvider.sendCommand(device.id, feature, val);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSensorRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _featureLabel(String feature) {
    switch (feature) {
      case 'relay':
        return 'Relay';
      case 'led':
        return 'LED';
      case 'temperature':
        return 'Temperature';
      case 'humidity':
        return 'Humidity';
      case 'motion':
        return 'Motion';
      default:
        return feature;
    }
  }
}
