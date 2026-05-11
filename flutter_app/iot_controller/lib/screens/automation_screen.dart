import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/automation.dart';
import '../models/device.dart';
import '../providers/automation_provider.dart';
import '../providers/device_provider.dart';

class AutomationScreen extends StatelessWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AutomationProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          body: Column(
            children: [
              // Show current app time for debugging schedule issues
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                child: Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Builder(builder: (ctx) {
                      final now = DateTime.now();
                      final h = now.hour.toString().padLeft(2, '0');
                      final m = now.minute.toString().padLeft(2, '0');
                      final s = now.second.toString().padLeft(2, '0');
                      return Text(
                        'App time: $h:$m:$s (24h)',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      );
                    }),
                  ],
                ),
              ),
              Expanded(
                child: provider.automations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.schedule,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No automations yet',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600])),
                            const SizedBox(height: 8),
                            Text(
                                'Create schedules, conditions,\nsunrise/sunset scenes, or timers',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[500]),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.automations.length,
                        itemBuilder: (context, index) {
                          final auto = provider.automations[index];
                          return _AutomationCard(
                              automation: auto);
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAutomationSheet(context),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  void _showAutomationSheet(BuildContext context, {Automation? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AutomationFormSheet(existing: existing),
    );
  }
}

class _AutomationCard extends StatelessWidget {
  final Automation automation;
  const _AutomationCard({required this.automation});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AutomationProvider>();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getIcon(), color: _getColor(), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(automation.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        '${automation.typeLabel} \u2022 ${automation.timeText}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: automation.enabled,
                  onChanged: (_) =>
                      provider.toggleAutomation(automation.id),
                ),
              ],
            ),
            if (automation.type == AutomationType.condition)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 40),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.deepOrange[200]!),
                  ),
                  child: Text(
                    'IF ${automation.conditionText}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.deepOrange[800],
                    ),
                  ),
                ),
              ),
            if (automation.type == AutomationType.schedule &&
                automation.repeatDays.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 40),
                child: Text(automation.repeatText,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
              ),
            if (automation.type == AutomationType.countdown) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 40),
                  if (automation.isCountdownRunning)
                    Text(
                      '${automation.countdownRemaining}s remaining',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700]),
                    )
                  else
                    Text(automation.timeText,
                        style: const TextStyle(fontSize: 14)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (automation.isCountdownRunning) {
                        provider.stopCountdown(automation.id);
                      } else {
                        provider.startCountdown(automation.id);
                      }
                    },
                    icon: Icon(automation.isCountdownRunning
                        ? Icons.stop
                        : Icons.play_arrow),
                    label: Text(automation.isCountdownRunning
                        ? 'Stop'
                        : 'Start'),
                  ),
                ],
              ),
            ],
            if (automation.actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 40),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: automation.actions.map((a) {
                    return Chip(
                      label: Text(
                        '${a.deviceId}/${a.feature} ${a.state ? "ON" : "OFF"}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      labelPadding:
                          const EdgeInsets.symmetric(horizontal: 6),
                    );
                  }).toList(),
                ),
              ),

            // Last executed info
            Builder(builder: (ctx) {
              final lastExec =
                  provider.lastExecutedTime(automation.id);
              if (lastExec == null) return const SizedBox.shrink();
              final h = lastExec.hour.toString().padLeft(2, '0');
              final m = lastExec.minute.toString().padLeft(2, '0');
              final s = lastExec.second.toString().padLeft(2, '0');
              return Padding(
                padding: const EdgeInsets.only(top: 4, left: 40),
                child: Text(
                  'Last fired: $h:$m:$s',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.green[700],
                      fontStyle: FontStyle.italic),
                ),
              );
            }),

            // Run Now, Edit & Delete buttons
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    provider.runNow(automation.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Executed: ${automation.name}'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: Icon(Icons.play_circle_outline,
                      size: 16, color: Colors.green[700]),
                  label: Text('Run Now',
                      style: TextStyle(color: Colors.green[700])),
                ),
                TextButton.icon(
                  onPressed: () => _showEditSheet(context),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => _confirmDelete(context),
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: Colors.red[400]),
                  label: Text('Delete',
                      style: TextStyle(color: Colors.red[400])),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AutomationFormSheet(existing: automation),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Automation'),
        content: Text('Delete "${automation.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context
                  .read<AutomationProvider>()
                  .removeAutomation(automation.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  IconData _getIcon() {
    switch (automation.type) {
      case AutomationType.schedule:
        return Icons.schedule;
      case AutomationType.sunrise:
        return Icons.wb_sunny;
      case AutomationType.sunset:
        return Icons.nightlight_round;
      case AutomationType.countdown:
        return Icons.timer;
      case AutomationType.condition:
        return Icons.rule;
    }
  }

  Color _getColor() {
    switch (automation.type) {
      case AutomationType.schedule:
        return Colors.blue;
      case AutomationType.sunrise:
        return Colors.orange;
      case AutomationType.sunset:
        return Colors.deepPurple;
      case AutomationType.countdown:
        return Colors.teal;
      case AutomationType.condition:
        return Colors.deepOrange;
    }
  }
}

// ── Shared Form Sheet (Create & Edit) ───────────────────────────────────────

class _AutomationFormSheet extends StatefulWidget {
  final Automation? existing;
  const _AutomationFormSheet({this.existing});

  @override
  State<_AutomationFormSheet> createState() => _AutomationFormSheetState();
}

class _AutomationFormSheetState extends State<_AutomationFormSheet> {
  late final TextEditingController _nameController;
  late AutomationType _type;
  late TimeOfDay _time;
  late Set<int> _repeatDays;
  late int _countdownMinutes;
  late List<AutomationAction> _actions;

  // Condition fields
  String? _condDeviceId;
  String? _condFeature;
  ConditionOperator? _condOp;
  double? _condNumValue;
  bool? _condBoolValue;
  final _condValueController = TextEditingController();

  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _type = e?.type ?? AutomationType.schedule;
    _time = TimeOfDay(hour: e?.hour ?? 8, minute: e?.minute ?? 0);
    _repeatDays = Set<int>.from(e?.repeatDays ?? []);
    _countdownMinutes = (e?.countdownSeconds ?? 300) ~/ 60;
    _actions = List<AutomationAction>.from(e?.actions ?? []);

    // Restore condition fields
    _condDeviceId = e?.conditionDeviceId;
    _condFeature = e?.conditionFeature;
    _condOp = e?.conditionOperator;
    _condNumValue = e?.conditionValue;
    _condBoolValue = e?.conditionBoolValue;
    if (_condNumValue != null) {
      _condValueController.text = _condNumValue.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _condValueController.dispose();
    super.dispose();
  }

  bool get _isFeatureBoolean {
    if (_condFeature == null) return false;
    return _condFeature == 'relay' ||
        _condFeature == 'led' ||
        _condFeature == 'motion';
  }

  bool get _isFeatureNumeric {
    if (_condFeature == null) return false;
    return _condFeature == 'temperature' ||
        _condFeature == 'humidity' ||
        _condFeature == 'motion_count';
  }

  @override
  Widget build(BuildContext context) {
    final deviceProvider = context.read<DeviceProvider>();
    final devices = deviceProvider.onlineDevices;
    final allDevices = deviceProvider.devices;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? 'Edit Automation' : 'New Automation',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Type selector — wrap for smaller screens
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _typeChip(AutomationType.schedule, 'Schedule', Icons.schedule),
                _typeChip(AutomationType.sunrise, 'Sunrise', Icons.wb_sunny),
                _typeChip(AutomationType.sunset, 'Sunset', Icons.nightlight),
                _typeChip(AutomationType.countdown, 'Timer', Icons.timer),
                _typeChip(AutomationType.condition, 'Condition', Icons.rule),
              ],
            ),
            const SizedBox(height: 12),

            // Time picker (for schedule)
            if (_type == AutomationType.schedule) ...[
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(
                    '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _time,
                    builder: (ctx, child) {
                      return MediaQuery(
                        data: MediaQuery.of(ctx).copyWith(
                            alwaysUse24HourFormat: true),
                        child: child!,
                      );
                    },
                  );
                  if (t != null) setState(() => _time = t);
                },
              ),
              const Text('Repeat on:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 4,
                children: List.generate(7, (i) {
                  const days = [
                    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
                  ];
                  return FilterChip(
                    label:
                        Text(days[i], style: const TextStyle(fontSize: 11)),
                    selected: _repeatDays.contains(i),
                    onSelected: (v) => setState(() {
                      v ? _repeatDays.add(i) : _repeatDays.remove(i);
                    }),
                  );
                }),
              ),
            ],

            // Countdown duration
            if (_type == AutomationType.countdown)
              Row(
                children: [
                  const Text('Duration (minutes): '),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 120,
                      divisions: 119,
                      value: _countdownMinutes.toDouble(),
                      label: '$_countdownMinutes min',
                      onChanged: (v) =>
                          setState(() => _countdownMinutes = v.round()),
                    ),
                  ),
                  Text('$_countdownMinutes'),
                ],
              ),

            // Condition configuration
            if (_type == AutomationType.condition) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepOrange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepOrange[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IF condition:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange[800],
                        )),
                    const SizedBox(height: 8),
                    // Device picker
                    DropdownButtonFormField<String>(
                      value: _condDeviceId,
                      decoration: const InputDecoration(
                        labelText: 'Device',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: allDevices.map((d) {
                        return DropdownMenuItem(
                          value: d.id,
                          child: Text('${d.id} (${d.typeLabel})',
                              style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() {
                        _condDeviceId = v;
                        _condFeature = null;
                        _condOp = null;
                        _condBoolValue = null;
                        _condNumValue = null;
                      }),
                    ),
                    const SizedBox(height: 8),
                    // Feature picker
                    if (_condDeviceId != null)
                      DropdownButtonFormField<String>(
                        value: _condFeature,
                        decoration: const InputDecoration(
                          labelText: 'Feature',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _getFeaturesForDevice(allDevices).map((f) {
                          return DropdownMenuItem(
                            value: f,
                            child: Text(f, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() {
                          _condFeature = v;
                          _condOp = null;
                          _condBoolValue = null;
                          _condNumValue = null;
                        }),
                      ),
                    const SizedBox(height: 8),
                    // Operator picker
                    if (_condFeature != null)
                      DropdownButtonFormField<ConditionOperator>(
                        value: _condOp,
                        decoration: const InputDecoration(
                          labelText: 'Operator',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _getOperatorsForFeature().map((op) {
                          return DropdownMenuItem(
                            value: op,
                            child: Text(Automation.opLabel(op),
                                style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _condOp = v),
                      ),
                    const SizedBox(height: 8),
                    // Value input
                    if (_condOp != null && _isFeatureBoolean)
                      DropdownButtonFormField<bool>(
                        value: _condBoolValue,
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('ON')),
                          DropdownMenuItem(value: false, child: Text('OFF')),
                        ],
                        onChanged: (v) =>
                            setState(() => _condBoolValue = v),
                      ),
                    if (_condOp != null && _isFeatureNumeric)
                      TextField(
                        controller: _condValueController,
                        decoration: InputDecoration(
                          labelText: _condFeature == 'temperature'
                              ? 'Value (\u00B0C)'
                              : _condFeature == 'humidity'
                                  ? 'Value (%)'
                                  : 'Value',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (v) {
                          _condNumValue = double.tryParse(v);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 12),
            const Text('THEN actions:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No online devices'),
              )
            else
              ...devices.expand((device) => device.features
                  .where((f) =>
                      f != 'temperature' &&
                      f != 'humidity' &&
                      f != 'motion_count')
                  .map((feature) {
                final existing = _actions
                    .where((a) =>
                        a.deviceId == device.id && a.feature == feature)
                    .toList();
                final isSelected = existing.isNotEmpty;
                final currentState =
                    isSelected ? existing.first.state : true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _actions.add(AutomationAction(
                                deviceId: device.id,
                                feature: feature,
                                state: true));
                          } else {
                            _actions.removeWhere((a) =>
                                a.deviceId == device.id &&
                                a.feature == feature);
                          }
                        }),
                      ),
                      Expanded(
                        child: Text('${device.id} \u2014 $feature',
                            style: const TextStyle(fontSize: 13)),
                      ),
                      if (isSelected)
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                                value: true,
                                label: Text('ON',
                                    style: TextStyle(fontSize: 11))),
                            ButtonSegment(
                                value: false,
                                label: Text('OFF',
                                    style: TextStyle(fontSize: 11))),
                          ],
                          selected: {currentState},
                          onSelectionChanged: (v) => setState(() {
                            _actions.removeWhere((a) =>
                                a.deviceId == device.id &&
                                a.feature == feature);
                            _actions.add(AutomationAction(
                                deviceId: device.id,
                                feature: feature,
                                state: v.first));
                          }),
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                );
              })),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave() ? () => _save(context) : null,
                child: Text(isEditing
                    ? 'Save Changes'
                    : 'Create Automation'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(AutomationType type, String label, IconData icon) {
    final selected = _type == type;
    return ChoiceChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _type = type),
    );
  }

  List<String> _getFeaturesForDevice(List<IoTDevice> allDevices) {
    final device = allDevices.where((d) => d.id == _condDeviceId).toList();
    if (device.isEmpty) return [];
    return device.first.features;
  }

  List<ConditionOperator> _getOperatorsForFeature() {
    if (_isFeatureBoolean) {
      return [ConditionOperator.eq, ConditionOperator.neq];
    }
    return ConditionOperator.values;
  }

  bool _canSave() {
    if (_nameController.text.isEmpty || _actions.isEmpty) return false;
    if (_type == AutomationType.condition) {
      if (_condDeviceId == null ||
          _condFeature == null ||
          _condOp == null) return false;
      if (_isFeatureBoolean && _condBoolValue == null) return false;
      if (_isFeatureNumeric && _condNumValue == null) return false;
    }
    return true;
  }

  void _save(BuildContext context) {
    final provider = context.read<AutomationProvider>();
    final automation = Automation(
      id: widget.existing?.id ?? provider.generateId(),
      name: _nameController.text.trim(),
      type: _type,
      enabled: widget.existing?.enabled ?? true,
      hour: _type == AutomationType.schedule ? _time.hour : null,
      minute: _type == AutomationType.schedule ? _time.minute : null,
      repeatDays: _repeatDays.toList()..sort(),
      countdownSeconds: _type == AutomationType.countdown
          ? _countdownMinutes * 60
          : null,
      conditionDeviceId:
          _type == AutomationType.condition ? _condDeviceId : null,
      conditionFeature:
          _type == AutomationType.condition ? _condFeature : null,
      conditionOperator:
          _type == AutomationType.condition ? _condOp : null,
      conditionValue:
          _type == AutomationType.condition ? _condNumValue : null,
      conditionBoolValue:
          _type == AutomationType.condition ? _condBoolValue : null,
      actions: _actions,
    );

    if (isEditing) {
      provider.updateAutomation(automation);
    } else {
      provider.addAutomation(automation);
    }
    Navigator.pop(context);
  }
}
