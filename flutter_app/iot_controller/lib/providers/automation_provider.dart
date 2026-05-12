import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/automation.dart';
import '../services/mqtt_service.dart';
import '../services/api_service.dart';

/// MQTT topic for syncing automation rules to server
const _kRulesTopic = 'home/automation/rules';

/// MQTT topic for requesting a countdown start on the server
const _kCountdownTopic = 'home/automation/countdown';

/// MQTT topic for server-side execution log (subscribe to receive)
const _kLogTopic = 'home/automation/log';

class AutomationProvider extends ChangeNotifier {
  final MqttService _mqttService;
  final ApiService _api = ApiService();
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

  final Map<String, DateTime> _lastExecuted = {};
  DateTime? lastExecutedTime(String id) => _lastExecuted[id];

  void _subscribeLog() {
    _mqttService.subscribe(_kLogTopic, (topic, payload) {
      final id = payload['id'] as String?;
      if (id != null) {
        _lastExecuted[id] = DateTime.now();
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

  void _subscribeRules() {
    _mqttService.subscribe(_kRulesTopic, (topic, payload) {
      final senderId = payload['senderId'] as String?;
      if (senderId == _localSenderId) return;
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

  void _mergeRules(List<Automation> incoming) {
    final localById = {for (final a in _automations) a.id: a};
    final remoteById = {for (final a in incoming) a.id: a};
    final allIds = {...localById.keys, ...remoteById.keys};
    final merged = <Automation>[];
    for (final id in allIds) {
      final local = localById[id];
      final remote = remoteById[id];
      if (local != null && remote != null) {
        merged.add(remote.lastModified >= local.lastModified ? remote : local);
      } else if (remote != null) {
        merged.add(remote);
      } else if (local != null) {
        merged.add(local);
      }
    }
    _automations.clear();
    _automations.addAll(merged);
  }

  void _publishRules() {
    final data = _automations.map((a) => a.toJson()).toList();
    _mqttService.publish(
      _kRulesTopic,
      {'rules': data, 'senderId': _localSenderId},
      retain: true,
    );
  }

  /// Sync rules to server via API (primary) and MQTT (fallback).
  Future<void> syncToServer() async {
    _publishRules();

    // Also sync via REST API if configured
    if (_api.isConfigured && _api.hasToken) {
      try {
        final serverAutomations = await _api.fetchAutomations();
        if (serverAutomations.isNotEmpty) {
          debugPrint('[AUTO] Fetched ${serverAutomations.length} automations from API');
        }
      } catch (e) {
        debugPrint('[AUTO] API sync failed: $e');
      }
    }
  }

  void addAutomation(Automation automation) {
    _automations.add(automation);
    _saveAutomations();
    _publishRules();
    _syncToApi(automation);
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

    // Delete from API
    if (_api.isConfigured && _api.hasToken) {
      _api.deleteAutomation(id).catchError((_) {});
    }

    notifyListeners();
  }

  void toggleAutomation(String id) {
    final auto = _automations.firstWhere((a) => a.id == id);
    auto.enabled = !auto.enabled;
    auto.lastModified = DateTime.now().millisecondsSinceEpoch;
    _saveAutomations();
    _publishRules();

    // Toggle via API
    if (_api.isConfigured && _api.hasToken) {
      _api.toggleAutomation(id).catchError((_) {});
    }

    notifyListeners();
  }

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

  void startCountdown(String id) {
    final auto = _automations.firstWhere((a) => a.id == id);
    auto.countdownStart = DateTime.now();
    _saveAutomations();

    // Try API first, fallback to MQTT
    if (_api.isConfigured && _api.hasToken) {
      _api.startCountdown(id).catchError((_) {
        // Fallback to MQTT
        _mqttService.publish(_kCountdownTopic, {
          'id': auto.id,
          'action': 'start',
          'seconds': auto.countdownSeconds,
          'commands': auto.actions.map((a) => a.toJson()).toList(),
        });
      });
    } else {
      _mqttService.publish(_kCountdownTopic, {
        'id': auto.id,
        'action': 'start',
        'seconds': auto.countdownSeconds,
        'commands': auto.actions.map((a) => a.toJson()).toList(),
      });
    }

    notifyListeners();
  }

  void stopCountdown(String id) {
    final auto = _automations.firstWhere((a) => a.id == id);
    auto.countdownStart = null;
    _saveAutomations();

    if (_api.isConfigured && _api.hasToken) {
      _api.cancelCountdown(id).catchError((_) {});
    }

    _mqttService.publish(_kCountdownTopic, {
      'id': auto.id,
      'action': 'stop',
    });
    notifyListeners();
  }

  /// Sync a single automation to the API backend
  Future<void> _syncToApi(Automation auto) async {
    if (!_api.isConfigured || !_api.hasToken) return;
    try {
      await _api.createAutomation(_automationToApiJson(auto));
    } catch (e) {
      debugPrint('[AUTO] API create failed: $e');
    }
  }

  Map<String, dynamic> _automationToApiJson(Automation auto) {
    String apiType;
    switch (auto.type) {
      case AutomationType.schedule:
      case AutomationType.sunrise:
      case AutomationType.sunset:
        apiType = 'schedule';
        break;
      case AutomationType.countdown:
        apiType = 'countdown';
        break;
      case AutomationType.condition:
        apiType = 'trigger';
        break;
    }

    return {
      'name': auto.name,
      'automation_type': apiType,
      'enabled': auto.enabled,
      'config': auto.toJson(),
    };
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
