import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/device_provider.dart';
import '../models/notification_item.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, provider, child) {
        final notifications = provider.notifications;

        if (notifications.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No notifications yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Device events will appear here',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Action bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => provider.markAllRead(),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Mark all read'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _confirmClear(context, provider),
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Clear all'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Notification list
            Expanded(
              child: ListView.separated(
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = notifications[index];
                  return _NotificationTile(item: item);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmClear(BuildContext context, DeviceProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Notifications'),
        content: const Text('Are you sure you want to clear all notifications?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              provider.clearNotifications();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;

  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: item.isRead ? null : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getColor().withOpacity(0.15),
          child: Icon(_getIcon(), color: _getColor(), size: 20),
        ),
        title: Text(
          item.message,
          style: TextStyle(
            fontSize: 14,
            fontWeight: item.isRead ? FontWeight.normal : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _formatTime(item.timestamp),
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        trailing: !item.isRead
            ? Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              )
            : null,
      ),
    );
  }

  IconData _getIcon() {
    switch (item.type) {
      case NotificationType.stateChange:
        return Icons.power_settings_new;
      case NotificationType.deviceOnline:
        return Icons.wifi;
      case NotificationType.deviceOffline:
        return Icons.wifi_off;
      case NotificationType.otaUpdate:
        return Icons.system_update;
    }
  }

  Color _getColor() {
    switch (item.type) {
      case NotificationType.stateChange:
        return Colors.blue;
      case NotificationType.deviceOnline:
        return Colors.green;
      case NotificationType.deviceOffline:
        return Colors.red;
      case NotificationType.otaUpdate:
        return Colors.orange;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, HH:mm').format(time);
  }
}
