import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/automation.dart';
import '../services/mqtt_service.dart';

/// MQTT topic for syncing automation rules to server
const _kRulesTopic = 'home/automation/rules';

/// MQTT topic for requesting a countdown start on the server
const _kCountdownTopic = 'home/automation/countdown';

/// MQTT topic for server-side execution log (subscribe to receive)
const _kLogTopic = 'home/automation/log';

class AutomationProvider extends ChangeNotifier {
  final MqttService _mqttService;
  final List<Automation> _automations = [];
  final _uuid = const Uuid();
  String _localSenderId = '';
  bool _ignoreNextEcho = false;

  List<Automation> get automations => List.unmodifiable(_automations);

  AutomationProvider(this._mqttService) {
    _localSenderId = 'flutter_${_uuid.v4().substring(0, 8)}';
    _loadAutomations();
    _subscribeLog();
    _subscribeRules();
  }

  // Track last execution time reported by server
  final Map<String, DateTime> _lastExecuted = {};
  DateTime? lastExecutedTime(String id) => _lastExecuted[id];

  void _subscribeLog() {
    _mqttService.subscribe(_kLogTopic, (topic, payload) {
      final id = payload['id'] as String?;
      if (id != null) {
        _lastExecuted[id] = DateTime.now();

        // Reset countdown state when server reports completion
        final type = payload['type'] as String?;
        if (type == 'countdown') {
          try {
            final auto = _automations.firstWhere((a) => a.id == id);
            auto.countdownStart = null;
            _saveAutomations();
          } catch (_) {}
        }

        notifyListeners();
      }
    });
  }

  /// Subscribe to rules topic to sync automations across devices.
  /// Uses merge-based sync: per-rule lastModified timestamps determine
  /// which version wins, preventing race conditions when two phones
  /// toggle enable/disable at nearly the same time.
  void _subscribeRules() {
    _mqttService.subscribe(_kRulesTopic, (topic, payload) {
      final senderId = payload['senderId'] as String?;
      if (senderId == _localSenderId) {
        debugPrint('[AUTO] Ignoring own echo');
        return;
      }
      if (_ignoreNextEcho) {
        _ignoreNextEcho = false;
        return;
      }

      final rules = payload['rules'] as List?;
      if (rules == null) return;

      final incoming = rules
          .map((e) => Automation.fromJson(e as Map<String, dynamic>))
          .toList();

      _mergeRules(incoming);
      _saveAutomations();
      notifyListeners();
      debugPrint('[AUTO] Merged ${incoming.length} rules from $senderId');
    });
  }

  /// Merge incoming rules with local rules using lastModified timestamps.
  /// For each rule: keep the version with the newer lastModified.
  /// New remote rules are added; rules only existing locally are kept.
  void _mergeRules(List<Automation> incoming) {
    final localById = {for (final a in _automations) a.id: a};
    final remoteById = {for (final a in incoming) a.id: a};
    final allIds = {...localById.keys, ...remoteById.keys};

    final merged = <Automation>[];
    for (final id in allIds) {
      final local = localById[id];
      final remote = remoteById[id];
      if (local != null && remote != null) {
        merged.add(
          remote.lastModified >= local.lastModified ? remote : local,
        );
      } else if (remote != null) {
        merged.add(remote);
      } else if (local != null) {
        merged.add(local);
      }
    }
    _automations.clear();
    _automations.addAll(merged);
  }

  /// Publish all automation rules to MQTT broker (retained).
  /// Includes senderId so other devices can distinguish the source.
  void _publishRules() {
    final data = _automations.map((a) => a.toJson()).toList();
    _mqttService.publish(
      _kRulesTopic,
      {'rules': data, 'senderId': _localSenderId},
      retain: true,
    );
    debugPrint('[AUTO] Published ${data.length} rules to MQTT');
  }

  /// Sync rules to server. Called after any change and on reconnect.
  void syncToServer() {
    _publishRules();
  }

  void addAutomation(Automation automation) {
    _automations.add(automation);
    _saveAutomations();
    _publishRules();
    notifyListeners();
  }

  void updateAutomation(Automation updated) {
    final index = _automations.indexWhere((a) => a.id == updated.id);
    if (index >= 0) {
      updated.lastModified = DateTime.now().millisecondsSinceEpoch;
      _automations[index] = updated;
      _saveAutomations();
      _publishRules();
      notifyListeners();
    }
  }

  void removeAutomation(String id) {
    _automations.removeWhere((a) => a.id == id);
    _saveAutomations();
    _ignoreNextEcho = true;
    _publishRules();
    notifyListeners();
  }

  void toggleAutomation(String id) {
    final auto = _automations.firstWhere((a) => a.id == id);
    auto.enabled = !auto.enabled;
    auto.lastModified = DateTime.now().millisecondsSinceEpoch;
    _saveAutomations();
    _publishRules();
    notifyListeners();
  }

  /// Run automation immediately by publishing command to each action's device.
  void runNow(String id) {
    final auto = _automations.firstWhere((a) => a.id == id);
    for (final action in auto.actions) {
      _mqttService.publish(
        'v1/devices/${action.deviceId}/command',
        {'feature': action.feature, 'state': action.state},
      );
    }
    _lastExecuted[auto.id] = DateTime.now();
    notifyListeners();
  }

  /// Start a countdown on the server.
  /// Server-side script handles the actual timer.
  void startCountdown(String id) {
    final auto = _automations.firstWhere((a) => a.id == id);
    auto.countdownStart = DateTime.now();
    _saveAutomations();
    _mqttService.publish(_kCountdownTopic, {
      'id': auto.id,
      'action': 'start',
      'seconds': auto.countdownSeconds,
      'commands': auto.actions.map((a) => a.toJson()).toList(),
    });
    notifyListeners();
  }

  /// Stop a running countdown on the server.
  void stopCountdown(String id) {
    final auto = _automations.firstWhere((a) => a.id == id);
    auto.countdownStart = null;
    _saveAutomations();
    _mqttService.publish(_kCountdownTopic, {
      'id': auto.id,
      'action': 'stop',
    });
    notifyListeners();
  }

  String generateId() => _uuid.v4();

  Future<void> _loadAutomations() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('automations');
    if (data != null) {
      final list = jsonDecode(data) as List;
      _automations.clear();
      _automations.addAll(list.map((e) => Automation.fromJson(e)));
      notifyListeners();
    }
  }

  Future<void> _saveAutomations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'automations',
      jsonEncode(_automations.map((a) => a.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _mqttService.unsubscribe(_kLogTopic);
    _mqttService.unsubscribe(_kRulesTopic);
    super.dispose();
  }
}
