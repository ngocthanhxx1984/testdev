enum DeviceStatus { online, offline, unknown }

class IoTDevice {
  final String id;
  final String type;
  final String firmwareVersion;
  final List<String> features;
  DeviceStatus status;
  Map<String, dynamic> featureStates;
  int? rssi;
  int? uptime;
  String room;
  DateTime lastSeen;

  IoTDevice({
    required this.id,
    required this.type,
    required this.firmwareVersion,
    required this.features,
    this.status = DeviceStatus.unknown,
    Map<String, dynamic>? featureStates,
    this.rssi,
    this.uptime,
    this.room = 'Unassigned',
    DateTime? lastSeen,
  })  : featureStates =
            featureStates ?? {for (var f in features) f: false},
        lastSeen = lastSeen ?? DateTime.now();

  factory IoTDevice.fromDiscovery(Map<String, dynamic> json) {
    final features = List<String>.from(json['features'] ?? []);
    Map<String, dynamic> defaultStates = {};
    for (var f in features) {
      if (f == 'temperature' || f == 'humidity' || f == 'motion_count') {
        defaultStates[f] = 0.0;
      } else {
        defaultStates[f] = false;
      }
    }
    return IoTDevice(
      id: json['id'] ?? '',
      type: json['type'] ?? 'unknown',
      firmwareVersion: json['v'] ?? '0.0.0',
      features: features,
      featureStates: defaultStates,
      status: DeviceStatus.online,
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'v': firmwareVersion,
        'features': features,
        'status': status.index,
        'featureStates': featureStates,
        'rssi': rssi,
        'uptime': uptime,
        'room': room,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory IoTDevice.fromJson(Map<String, dynamic> json) {
    final features = List<String>.from(json['features'] ?? []);
    final states = Map<String, dynamic>.from(json['featureStates'] ?? {});
    return IoTDevice(
      id: json['id'] ?? '',
      type: json['type'] ?? 'unknown',
      firmwareVersion: json['v'] ?? '0.0.0',
      features: features,
      featureStates: states,
      status: DeviceStatus.values[json['status'] ?? 2],
      rssi: json['rssi'],
      uptime: json['uptime'],
      room: json['room'] ?? 'Unassigned',
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  bool get isSensor => type == 'esp8266_aht10' || type == 'esp8266_pir';
  bool get hasTemperature => features.contains('temperature');
  bool get hasHumidity => features.contains('humidity');
  bool get hasMotion => features.contains('motion');

  double? get temperature => featureStates['temperature'] is num
      ? (featureStates['temperature'] as num).toDouble()
      : null;

  double? get humidity => featureStates['humidity'] is num
      ? (featureStates['humidity'] as num).toDouble()
      : null;

  bool get motionDetected => featureStates['motion'] == true;

  void updateState(Map<String, dynamic> json) {
    for (var feature in features) {
      if (json.containsKey(feature)) {
        featureStates[feature] = json[feature];
      }
    }
    if (json.containsKey('motion_count')) {
      featureStates['motion_count'] = json['motion_count'];
    }
    if (json.containsKey('rssi')) rssi = json['rssi'] as int?;
    if (json.containsKey('uptime')) uptime = json['uptime'] as int?;
    lastSeen = DateTime.now();
  }

  void updateStatus(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? '';
    status = statusStr == 'online' ? DeviceStatus.online : DeviceStatus.offline;
    lastSeen = DateTime.now();
  }

  String get statusText {
    switch (status) {
      case DeviceStatus.online:
        return 'Online';
      case DeviceStatus.offline:
        return 'Offline';
      case DeviceStatus.unknown:
        return 'Unknown';
    }
  }

  String get typeLabel {
    switch (type) {
      case 'esp8266':
        return 'Relay/LED';
      case 'esp8266_aht10':
        return 'Temp/Humidity';
      case 'esp8266_pir':
        return 'Motion Sensor';
      default:
        return type;
    }
  }

  IconName get typeIcon {
    switch (type) {
      case 'esp8266':
        return IconName.developerBoard;
      case 'esp8266_aht10':
        return IconName.thermostat;
      case 'esp8266_pir':
        return IconName.sensors;
      default:
        return IconName.memory;
    }
  }
}

enum IconName { developerBoard, thermostat, sensors, memory }
