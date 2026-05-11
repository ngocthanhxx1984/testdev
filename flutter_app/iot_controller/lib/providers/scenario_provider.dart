import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/smart_scenario.dart';
import 'device_provider.dart';

class ScenarioProvider extends ChangeNotifier {
  final DeviceProvider _deviceProvider;
  final List<SmartScenario> _scenarios = [];
  final _uuid = const Uuid();

  List<SmartScenario> get scenarios => List.unmodifiable(_scenarios);

  ScenarioProvider(this._deviceProvider) {
    _loadScenarios();
  }

  Future<void> _loadScenarios() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('smart_scenarios');
    if (data != null) {
      final list = jsonDecode(data) as List;
      _scenarios.clear();
      _scenarios.addAll(list.map((e) => SmartScenario.fromJson(e)));
      notifyListeners();
    }
  }

  Future<void> _saveScenarios() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_scenarios.map((s) => s.toJson()).toList());
    await prefs.setString('smart_scenarios', data);
  }

  void addScenario(SmartScenario scenario) {
    _scenarios.add(scenario);
    _saveScenarios();
    notifyListeners();
  }

  void removeScenario(String id) {
    _scenarios.removeWhere((s) => s.id == id);
    _saveScenarios();
    notifyListeners();
  }

  void updateScenario(SmartScenario scenario) {
    final index = _scenarios.indexWhere((s) => s.id == scenario.id);
    if (index >= 0) {
      _scenarios[index] = scenario;
      _saveScenarios();
      notifyListeners();
    }
  }

  void executeScenario(SmartScenario scenario) {
    for (final action in scenario.actions) {
      _deviceProvider.sendCommand(
        action.deviceId,
        action.feature,
        action.state,
      );
    }
  }

  SmartScenario createAllOnScenario() {
    final devices = _deviceProvider.onlineDevices;
    final actions = <ScenarioAction>[];
    for (final device in devices) {
      for (final feature in device.features) {
        actions.add(ScenarioAction(
          deviceId: device.id,
          feature: feature,
          state: true,
        ));
      }
    }
    return SmartScenario(
      id: _uuid.v4(),
      name: 'Turn All On',
      icon: 'power',
      actions: actions,
    );
  }

  SmartScenario createAllOffScenario() {
    final devices = _deviceProvider.onlineDevices;
    final actions = <ScenarioAction>[];
    for (final device in devices) {
      for (final feature in device.features) {
        actions.add(ScenarioAction(
          deviceId: device.id,
          feature: feature,
          state: false,
        ));
      }
    }
    return SmartScenario(
      id: _uuid.v4(),
      name: 'Turn All Off',
      icon: 'power_off',
      actions: actions,
    );
  }

  String generateId() => _uuid.v4();
}
