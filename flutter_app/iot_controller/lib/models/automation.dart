enum AutomationType { schedule, sunrise, sunset, countdown, condition }

enum ConditionOperator { eq, neq, gt, lt, gte, lte }

class Automation {
  final String id;
  String name;
  AutomationType type;
  bool enabled;

  // For schedule type: specific time HH:MM
  int? hour;
  int? minute;
  List<int> repeatDays; // 0=Mon..6=Sun, empty=once

  // For countdown type: seconds remaining
  int? countdownSeconds;
  DateTime? countdownStart;

  // For condition type: entity state trigger
  String? conditionDeviceId;
  String? conditionFeature;
  ConditionOperator? conditionOperator;
  double? conditionValue; // for numeric comparisons
  bool? conditionBoolValue; // for bool comparisons (ON/OFF)

  // Actions to execute
  List<AutomationAction> actions;

  Automation({
    required this.id,
    required this.name,
    required this.type,
    this.enabled = true,
    this.hour,
    this.minute,
    this.repeatDays = const [],
    this.countdownSeconds,
    this.countdownStart,
    this.conditionDeviceId,
    this.conditionFeature,
    this.conditionOperator,
    this.conditionValue,
    this.conditionBoolValue,
    List<AutomationAction>? actions,
  }) : actions = actions ?? [];

  bool get isCountdownRunning =>
      type == AutomationType.countdown && countdownStart != null;

  int get countdownRemaining {
    if (!isCountdownRunning || countdownSeconds == null) return 0;
    final elapsed = DateTime.now().difference(countdownStart!).inSeconds;
    return (countdownSeconds! - elapsed).clamp(0, countdownSeconds!);
  }

  bool get isConditionNumeric {
    final op = conditionOperator;
    if (op == null) return false;
    return op == ConditionOperator.gt ||
        op == ConditionOperator.lt ||
        op == ConditionOperator.gte ||
        op == ConditionOperator.lte;
  }

  String get conditionText {
    if (type != AutomationType.condition) return '';
    final dev = conditionDeviceId ?? '?';
    final feat = conditionFeature ?? '?';
    final op = conditionOperator;
    if (op == ConditionOperator.eq || op == ConditionOperator.neq) {
      final boolVal = conditionBoolValue;
      if (boolVal != null) {
        final valStr = boolVal ? 'ON' : 'OFF';
        final opStr = op == ConditionOperator.eq ? '=' : '!=';
        return '$dev/$feat $opStr $valStr';
      }
      final numVal = conditionValue;
      final opStr = op == ConditionOperator.eq ? '=' : '!=';
      return '$dev/$feat $opStr ${numVal ?? '?'}';
    }
    final numVal = conditionValue ?? 0;
    final opStr = _opSymbol(op!);
    return '$dev/$feat $opStr $numVal';
  }

  static String _opSymbol(ConditionOperator op) {
    switch (op) {
      case ConditionOperator.eq:
        return '=';
      case ConditionOperator.neq:
        return '!=';
      case ConditionOperator.gt:
        return '>';
      case ConditionOperator.lt:
        return '<';
      case ConditionOperator.gte:
        return '>=';
      case ConditionOperator.lte:
        return '<=';
    }
  }

  static String opLabel(ConditionOperator op) {
    switch (op) {
      case ConditionOperator.eq:
        return 'Equal (=)';
      case ConditionOperator.neq:
        return 'Not equal (!=)';
      case ConditionOperator.gt:
        return 'Greater than (>)';
      case ConditionOperator.lt:
        return 'Less than (<)';
      case ConditionOperator.gte:
        return 'Greater or equal (>=)';
      case ConditionOperator.lte:
        return 'Less or equal (<=)';
    }
  }

  /// Evaluate if the condition is met given current device state value.
  bool evaluateCondition(dynamic currentValue) {
    if (conditionOperator == null) return false;

    // Boolean comparison (for relay, led, motion)
    if (conditionBoolValue != null) {
      final current = currentValue == true;
      switch (conditionOperator!) {
        case ConditionOperator.eq:
          return current == conditionBoolValue;
        case ConditionOperator.neq:
          return current != conditionBoolValue;
        default:
          return false;
      }
    }

    // Numeric comparison (for temperature, humidity)
    if (conditionValue != null && currentValue is num) {
      final cv = currentValue.toDouble();
      final tv = conditionValue!;
      switch (conditionOperator!) {
        case ConditionOperator.eq:
          return cv == tv;
        case ConditionOperator.neq:
          return cv != tv;
        case ConditionOperator.gt:
          return cv > tv;
        case ConditionOperator.lt:
          return cv < tv;
        case ConditionOperator.gte:
          return cv >= tv;
        case ConditionOperator.lte:
          return cv <= tv;
      }
    }

    return false;
  }

  String get typeLabel {
    switch (type) {
      case AutomationType.schedule:
        return 'Schedule';
      case AutomationType.sunrise:
        return 'Sunrise';
      case AutomationType.sunset:
        return 'Sunset';
      case AutomationType.countdown:
        return 'Countdown';
      case AutomationType.condition:
        return 'Condition';
    }
  }

  String get timeText {
    switch (type) {
      case AutomationType.schedule:
        if (hour != null && minute != null) {
          return '${hour!.toString().padLeft(2, '0')}:${minute!.toString().padLeft(2, '0')}';
        }
        return '--:--';
      case AutomationType.sunrise:
        return '06:00';
      case AutomationType.sunset:
        return '18:00';
      case AutomationType.countdown:
        if (countdownSeconds != null) {
          final m = countdownSeconds! ~/ 60;
          final s = countdownSeconds! % 60;
          return '${m}m ${s}s';
        }
        return '0m';
      case AutomationType.condition:
        return conditionText;
    }
  }

  String get repeatText {
    if (repeatDays.isEmpty) return 'Once';
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (repeatDays.length == 7) return 'Every day';
    if (repeatDays.length == 5 &&
        repeatDays.every((d) => d < 5)) return 'Weekdays';
    return repeatDays.map((d) => dayNames[d]).join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.index,
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'repeatDays': repeatDays,
        'countdownSeconds': countdownSeconds,
        'conditionDeviceId': conditionDeviceId,
        'conditionFeature': conditionFeature,
        'conditionOperator': conditionOperator?.index,
        'conditionValue': conditionValue,
        'conditionBoolValue': conditionBoolValue,
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  factory Automation.fromJson(Map<String, dynamic> json) {
    return Automation(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: AutomationType.values[json['type'] ?? 0],
      enabled: json['enabled'] ?? true,
      hour: json['hour'],
      minute: json['minute'],
      repeatDays: List<int>.from(json['repeatDays'] ?? []),
      countdownSeconds: json['countdownSeconds'],
      conditionDeviceId: json['conditionDeviceId'],
      conditionFeature: json['conditionFeature'],
      conditionOperator: json['conditionOperator'] != null
          ? ConditionOperator.values[json['conditionOperator']]
          : null,
      conditionValue: json['conditionValue'] != null
          ? (json['conditionValue'] as num).toDouble()
          : null,
      conditionBoolValue: json['conditionBoolValue'],
      actions: (json['actions'] as List?)
              ?.map((a) => AutomationAction.fromJson(a))
              .toList() ??
          [],
    );
  }
}

class AutomationAction {
  final String deviceId;
  final String feature;
  final bool state;

  AutomationAction({
    required this.deviceId,
    required this.feature,
    required this.state,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'feature': feature,
        'state': state,
      };

  factory AutomationAction.fromJson(Map<String, dynamic> json) {
    return AutomationAction(
      deviceId: json['deviceId'] ?? '',
      feature: json['feature'] ?? '',
      state: json['state'] ?? false,
    );
  }
}
