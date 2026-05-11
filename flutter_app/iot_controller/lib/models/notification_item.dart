enum NotificationType { stateChange, deviceOnline, deviceOffline, otaUpdate }

class NotificationItem {
  final String id;
  final String deviceId;
  final NotificationType type;
  final String message;
  final DateTime timestamp;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.message,
    required this.timestamp,
    this.isRead = false,
  });

  String get typeIcon {
    switch (type) {
      case NotificationType.stateChange:
        return 'power';
      case NotificationType.deviceOnline:
        return 'wifi';
      case NotificationType.deviceOffline:
        return 'wifi_off';
      case NotificationType.otaUpdate:
        return 'system_update';
    }
  }
}
