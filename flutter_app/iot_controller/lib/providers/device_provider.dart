import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device.dart';
import '../models/notification_item.dart';
import '../services/mqtt_service.dart';
import '../services/api_service.dart';

class DeviceProvider extends ChangeNotifier {
  final MqttService _mqttService;
  final ApiService _api = ApiService();
  final Map<String, IoTDevice> _devices = {};
  final List<NotificationItem> _notifications = [];
  final Map<String, String> _deviceRooms = {};
  final _uuid = const Uuid();

  List<IoTDevice> get devices => _devices.values.toList();
  List<IoTDevice> get onlineDevices =>
      _devices.values.where((d) => d.status == DeviceStatus.online).toList();
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Map<String, List<IoTDevice>> get devicesByRoom {
    final map = <String, List<IoTDevice>>{};
    for (final device in _devices.values) {
      map.putIfAbsent(device.room, () => []);
      map[device.room]!.add(device);
    }
    return map;
  }

  List<String> get rooms {
    final roomSet = _devices.values.map((d) => d.room).toSet();
    final sorted = roomSet.where((r) => r != 'Unassigned').toList()..sort();
    if (roomSet.contains('Unassigned')) sorted.add('Unassigned');
    return sorted;
  }

  DeviceProvider(this._mqttService) {
    _loadPersistedData();
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load room assignments
    final roomData = prefs.getString('device_rooms');
    if (roomData != null) {
      final map = jsonDecode(roomData) as Map<String, dynamic>;
      _deviceRooms.clear();
      map.forEach((k, v) => _deviceRooms[k] = v as String);
    }

    // Load persisted devices
    final devData = prefs.getString('devices_cache');
    if (devData != null) {
      final list = jsonDecode(devData) as List;
      for (final item in list) {
        final device = IoTDevice.fromJson(item);
        // All loaded devices start as offline until discovery confirms
        device.status = DeviceStatus.offline;
        _devices[device.id] = device;
      }
      debugPrint('[DEV] Loaded ${_devices.length} cached devices');
    }

    notifyListeners();
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _devices.values.map((d) => d.toJson()).toList();
    await prefs.setString('devices_cache', jsonEncode(list));
  }

  Future<void> _saveRoomAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_rooms', jsonEncode(_deviceRooms));
  }

  void assignRoom(String deviceId, String room) {
    _deviceRooms[deviceId] = room;
    final device = _devices[deviceId];
    if (device != null) {
      device.room = room;
    }
    _saveRoomAssignments();
    _saveDevices();
    notifyListeners();
  }

  void removeDevice(String deviceId) {
    _devices.remove(deviceId);
    _deviceRooms.remove(deviceId);
    _saveDevices();
    _saveRoomAssignments();
    notifyListeners();
  }

  void startListening() {
    _mqttService.subscribe('home/discovery', _onDiscovery);
    _mqttService.subscribe('v1/devices/+/status', _onDeviceStatus);
    _mqttService.subscribe('v1/devices/+/state', _onDeviceState);
  }

  void stopListening() {
    _mqttService.unsubscribe('home/discovery');
    _mqttService.unsubscribe('v1/devices/+/status');
    _mqttService.unsubscribe('v1/devices/+/state');
  }

  void _onDiscovery(String topic, Map<String, dynamic> payload) {
    final device = IoTDevice.fromDiscovery(payload);
    final isNew = !_devices.containsKey(device.id);

    // Restore room assignment
    if (_deviceRooms.containsKey(device.id)) {
      device.room = _deviceRooms[device.id]!;
    }

    if (!isNew) {
      // Preserve existing feature states — discovery should not reset them
      final existing = _devices[device.id]!;
      for (final entry in existing.featureStates.entries) {
        device.featureStates[entry.key] = entry.value;
      }
      device.room = existing.room;
    }

    device.status = DeviceStatus.online;
    _devices[device.id] = device;

    if (isNew) {
      _addNotification(
        deviceId: device.id,
        type: NotificationType.deviceOnline,
        message: '${device.typeLabel} "${device.id}" discovered',
      );

      _mqttService.subscribe('v1/devices/${device.id}/state', _onDeviceState);
      _mqttService.subscribe('v1/devices/${device.id}/status', _onDeviceStatus);
    }

    _saveDevices();
    notifyListeners();
  }

  void _onDeviceStatus(String topic, Map<String, dynamic> payload) {
    final deviceId = _extractDeviceId(topic);
    if (deviceId == null) return;

    final device = _devices[deviceId];
    if (device != null) {
      final oldStatus = device.status;
      device.updateStatus(payload);

      if (oldStatus != device.status) {
        _addNotification(
          deviceId: deviceId,
          type: device.status == DeviceStatus.online
              ? NotificationType.deviceOnline
              : NotificationType.deviceOffline,
          message: '"$deviceId" is now ${device.statusText}',
        );
      }
      _saveDevices();
      notifyListeners();
    }
  }

  void _onDeviceState(String topic, Map<String, dynamic> payload) {
    final deviceId = payload['id'] as String? ?? _extractDeviceId(topic);
    if (deviceId == null) return;

    final device = _devices[deviceId];
    if (device != null) {
      final oldStates = Map<String, dynamic>.from(device.featureStates);
      device.updateState(payload);
      device.status = DeviceStatus.online;

      for (var feature in device.features) {
        if (oldStates[feature] != device.featureStates[feature]) {
          if (feature == 'temperature' || feature == 'humidity') {
            // Don't spam notifications for sensor readings
          } else if (feature == 'motion' && device.featureStates[feature] == true) {
            _addNotification(
              deviceId: deviceId,
              type: NotificationType.stateChange,
              message: '$deviceId: Motion detected!',
            );
          } else if (feature != 'motion') {
            final state = device.featureStates[feature] == true ? 'ON' : 'OFF';
            _addNotification(
              deviceId: deviceId,
              type: NotificationType.stateChange,
              message: '$deviceId: $feature turned $state',
            );
          }
        }
      }
      _saveDevices();
      notifyListeners();
    }
  }

  void sendCommand(String deviceId, String feature, bool state) {
    // Optimistic update: immediately reflect new state in UI
    final device = _devices[deviceId];
    if (device != null) {
      final oldState = device.featureStates[feature];
      device.featureStates[feature] = state;

      if (oldState != state && feature != 'temperature' && feature != 'humidity') {
        final stateStr = state ? 'ON' : 'OFF';
        _addNotification(
          deviceId: deviceId,
          type: NotificationType.stateChange,
          message: '$deviceId: $feature turned $stateStr',
        );
      }
      notifyListeners();
    }

    // Send via API if available, fallback to MQTT
    if (_api.isConfigured && _api.hasToken) {
      _api.sendCommand(deviceId, feature, state).catchError((_) {
        // Fallback to direct MQTT
        _mqttService.publish(
          'v1/devices/$deviceId/command',
          {'feature': feature, 'state': state},
        );
      });
    } else {
      _mqttService.publish(
        'v1/devices/$deviceId/command',
        {'feature': feature, 'state': state},
      );
    }
  }

  void sendOtaUpdate(String deviceId, String firmwareUrl) {
    _mqttService.publish(
      'v1/devices/$deviceId/ota',
      {'cmd': 'ota', 'url': firmwareUrl},
    );
    _addNotification(
      deviceId: deviceId,
      type: NotificationType.otaUpdate,
      message: 'OTA update sent to "$deviceId"',
    );
    notifyListeners();
  }

  void markAllRead() {
    for (var n in _notifications) { n.isRead = true; }
    notifyListeners();
  }

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  void _addNotification({
    required String deviceId,
    required NotificationType type,
    required String message,
  }) {
    _notifications.insert(0, NotificationItem(
      id: _uuid.v4(),
      deviceId: deviceId,
      type: type,
      message: message,
      timestamp: DateTime.now(),
    ));
    if (_notifications.length > 100) {
      _notifications.removeRange(100, _notifications.length);
    }
  }

  String? _extractDeviceId(String topic) {
    final parts = topic.split('/');
    if (parts.length >= 3) return parts[2];
    return null;
  }
}
