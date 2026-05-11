class ScenarioAction {
  final String deviceId;
  final String feature;
  final bool state;

  ScenarioAction({
    required this.deviceId,
    required this.feature,
    required this.state,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'feature': feature,
        'state': state,
      };

  factory ScenarioAction.fromJson(Map<String, dynamic> json) {
    return ScenarioAction(
      deviceId: json['deviceId'] ?? '',
      feature: json['feature'] ?? '',
      state: json['state'] ?? false,
    );
  }
}

class SmartScenario {
  final String id;
  String name;
  String icon;
  List<ScenarioAction> actions;

  SmartScenario({
    required this.id,
    required this.name,
    this.icon = 'auto_awesome',
    List<ScenarioAction>? actions,
  }) : actions = actions ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  factory SmartScenario.fromJson(Map<String, dynamic> json) {
    return SmartScenario(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      icon: json['icon'] ?? 'auto_awesome',
      actions: (json['actions'] as List?)
              ?.map((a) => ScenarioAction.fromJson(a))
              .toList() ??
          [],
    );
  }
}
