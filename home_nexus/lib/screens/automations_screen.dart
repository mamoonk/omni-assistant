import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../state/automations_provider.dart';
import '../state/device_providers.dart';
import '../state/ha_connection.dart' show homeLocationProvider;
import '../state/scenes_provider.dart';

class AutomationsScreen extends ConsumerWidget {
  const AutomationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final automations = ref.watch(automationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Automations')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New automation',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AutomationEditorScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: automations.isEmpty
          ? const Center(child: Text('No automations yet — tap + to create one'))
          : ListView(
              children: [
                for (final automation in automations)
                  Dismissible(
                    key: ValueKey(automation.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete),
                    ),
                    onDismissed: (_) => ref
                        .read(automationsProvider.notifier)
                        .remove(automation.id),
                    child: ListTile(
                      title: Text(automation.name),
                      subtitle: Text(_describe(ref, automation)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AutomationEditorScreen(initial: automation),
                        ),
                      ),
                      trailing: Switch(
                        value: automation.enabled,
                        onChanged: (v) => ref
                            .read(automationsProvider.notifier)
                            .toggle(automation.id, v),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _describe(WidgetRef ref, Automation automation) {
    final devices = ref.read(devicesProvider);
    String deviceName(String id) =>
        devices.where((d) => d.id == id).firstOrNull?.name ?? 'missing device';

    final when = switch (automation.trigger) {
      DeviceTrigger t =>
        'When ${deviceName(t.deviceId)} ${t.capabilityType} ${t.op} ${t.value}',
      TimeTrigger t =>
        'At ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      SunTrigger t => 'At ${t.event}'
          '${t.offsetMinutes == 0 ? '' : ' ${t.offsetMinutes > 0 ? '+' : ''}${t.offsetMinutes}m'}',
    };
    return '$when → ${automation.actions.length} action(s)';
  }
}

enum _TriggerKind { device, time, sun }

class AutomationEditorScreen extends ConsumerStatefulWidget {
  /// When set, the editor modifies this automation instead of creating one.
  final Automation? initial;
  const AutomationEditorScreen({super.key, this.initial});

  @override
  ConsumerState<AutomationEditorScreen> createState() =>
      _AutomationEditorScreenState();
}

class _AutomationEditorScreenState
    extends ConsumerState<AutomationEditorScreen> {
  final _nameCtrl = TextEditingController();

  // trigger
  _TriggerKind _kind = _TriggerKind.device;
  String? _triggerDeviceId;
  String? _triggerCapability;
  String _triggerOp = '==';
  final _triggerValueCtrl = TextEditingController();
  bool _triggerBoolValue = true;
  TimeOfDay _triggerTime = const TimeOfDay(hour: 8, minute: 0);
  String _sunEvent = 'sunset';
  final _sunOffsetCtrl = TextEditingController(text: '0');

  // condition
  bool _useTimeRange = false;
  TimeOfDay _rangeStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _rangeEnd = const TimeOfDay(hour: 6, minute: 0);

  // actions
  final _actions = <AutomationAction>[];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;

    _nameCtrl.text = initial.name;
    _actions.addAll(initial.actions);
    switch (initial.trigger) {
      case DeviceTrigger t:
        _kind = _TriggerKind.device;
        _triggerDeviceId = t.deviceId;
        _triggerCapability = t.capabilityType;
        _triggerOp = t.op;
        if (t.value is bool) {
          _triggerBoolValue = t.value as bool;
        } else {
          _triggerValueCtrl.text = '${t.value}';
        }
      case TimeTrigger t:
        _kind = _TriggerKind.time;
        _triggerTime = TimeOfDay(hour: t.hour, minute: t.minute);
      case SunTrigger t:
        _kind = _TriggerKind.sun;
        _sunEvent = t.event;
        _sunOffsetCtrl.text = '${t.offsetMinutes}';
    }
    final condition = initial.condition;
    if (condition != null) {
      _useTimeRange = true;
      _rangeStart = TimeOfDay(
          hour: condition.startMinutes ~/ 60,
          minute: condition.startMinutes % 60);
      _rangeEnd = TimeOfDay(
          hour: condition.endMinutes ~/ 60, minute: condition.endMinutes % 60);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _triggerValueCtrl.dispose();
    _sunOffsetCtrl.dispose();
    super.dispose();
  }

  UniversalDevice? get _triggerDevice => ref
      .read(devicesProvider)
      .where((d) => d.id == _triggerDeviceId)
      .firstOrNull;

  bool get _triggerIsBool {
    final cap = _triggerCapability;
    return cap == CapabilityType.powerSwitch ||
        cap == CapabilityType.motion ||
        cap == CapabilityType.contact;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name and at least one action required')));
      return;
    }

    final Trigger trigger;
    switch (_kind) {
      case _TriggerKind.time:
        trigger =
            TimeTrigger(hour: _triggerTime.hour, minute: _triggerTime.minute);
      case _TriggerKind.sun:
        if (ref.read(homeLocationProvider) == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Set your home location in Settings first')));
          return;
        }
        trigger = SunTrigger(
          event: _sunEvent,
          offsetMinutes: int.tryParse(_sunOffsetCtrl.text) ?? 0,
        );
      case _TriggerKind.device:
        if (_triggerDeviceId == null || _triggerCapability == null) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pick a trigger device')));
          return;
        }
        trigger = DeviceTrigger(
          deviceId: _triggerDeviceId!,
          capabilityType: _triggerCapability!,
          op: _triggerIsBool ? '==' : _triggerOp,
          value: _triggerIsBool
              ? _triggerBoolValue
              : num.tryParse(_triggerValueCtrl.text) ?? 0,
        );
    }

    final automation = Automation(
      id: widget.initial?.id ??
          'auto_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      enabled: widget.initial?.enabled ?? true,
      trigger: trigger,
      condition: _useTimeRange
          ? TimeRangeCondition(
              startMinutes: _rangeStart.hour * 60 + _rangeStart.minute,
              endMinutes: _rangeEnd.hour * 60 + _rangeEnd.minute,
            )
          : null,
      actions: List.of(_actions),
    );
    await ref.read(automationsProvider.notifier).save(automation);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final scenes = ref.watch(scenesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New automation' : 'Edit automation'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          Text('When', style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<_TriggerKind>(
            segments: const [
              ButtonSegment(
                  value: _TriggerKind.device, label: Text('Device')),
              ButtonSegment(value: _TriggerKind.time, label: Text('Time')),
              ButtonSegment(value: _TriggerKind.sun, label: Text('Sun')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          if (_kind == _TriggerKind.time)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('At ${_triggerTime.format(context)}'),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final t = await showTimePicker(
                    context: context, initialTime: _triggerTime);
                if (t != null) setState(() => _triggerTime = t);
              },
            )
          else if (_kind == _TriggerKind.sun) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sunEvent,
                    decoration: const InputDecoration(
                        labelText: 'Event', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'sunrise', child: Text('Sunrise')),
                      DropdownMenuItem(value: 'sunset', child: Text('Sunset')),
                    ],
                    onChanged: (v) => setState(() => _sunEvent = v!),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _sunOffsetCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Offset (min)',
                      helperText: '-30 = before',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            if (ref.watch(homeLocationProvider) == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Requires a home location (Settings → Home location)',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12),
                ),
              ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _triggerDeviceId,
              decoration: const InputDecoration(
                  labelText: 'Device', border: OutlineInputBorder()),
              items: [
                for (final d in devices)
                  DropdownMenuItem(value: d.id, child: Text(d.name)),
              ],
              onChanged: (v) => setState(() {
                _triggerDeviceId = v;
                _triggerCapability = _triggerDevice?.primaryCapability;
              }),
            ),
            const SizedBox(height: 12),
            if (_triggerDevice != null) ...[
              DropdownButtonFormField<String>(
                initialValue: _triggerCapability,
                decoration: const InputDecoration(
                    labelText: 'Capability', border: OutlineInputBorder()),
                items: [
                  for (final c in _triggerDevice!.capabilities)
                    DropdownMenuItem(value: c.type, child: Text(c.type)),
                ],
                onChanged: (v) => setState(() => _triggerCapability = v),
              ),
              const SizedBox(height: 12),
              if (_triggerIsBool)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_triggerBoolValue
                      ? 'Becomes on / active'
                      : 'Becomes off / inactive'),
                  value: _triggerBoolValue,
                  onChanged: (v) => setState(() => _triggerBoolValue = v),
                )
              else
                Row(
                  children: [
                    DropdownButton<String>(
                      value: _triggerOp,
                      items: const [
                        DropdownMenuItem(value: '==', child: Text('=')),
                        DropdownMenuItem(value: '>', child: Text('>')),
                        DropdownMenuItem(value: '<', child: Text('<')),
                      ],
                      onChanged: (v) => setState(() => _triggerOp = v!),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _triggerValueCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Value', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
            ],
          ],
          const SizedBox(height: 20),
          Text('Only if', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Within a time window'),
            subtitle: _useTimeRange
                ? Text(
                    '${_rangeStart.format(context)} – ${_rangeEnd.format(context)}')
                : null,
            value: _useTimeRange,
            onChanged: (v) => setState(() => _useTimeRange = v),
          ),
          if (_useTimeRange)
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: _rangeStart);
                    if (t != null) setState(() => _rangeStart = t);
                  },
                  child: Text('From ${_rangeStart.format(context)}'),
                ),
                TextButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: _rangeEnd);
                    if (t != null) setState(() => _rangeEnd = t);
                  },
                  child: Text('To ${_rangeEnd.format(context)}'),
                ),
              ],
            ),
          const SizedBox(height: 20),
          Text('Then', style: Theme.of(context).textTheme.titleMedium),
          for (final (i, action) in _actions.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(switch (action) {
                SetStateAction a =>
                  'Set ${devices.where((d) => d.id == a.deviceId).firstOrNull?.name ?? '?'} '
                      '${a.capabilityType} = ${a.value}',
                RunSceneAction a =>
                  'Run scene ${scenes.where((s) => s.id == a.sceneId).firstOrNull?.name ?? '?'}',
              }),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() => _actions.removeAt(i)),
              ),
            ),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Device action'),
                onPressed: () async {
                  final action = await showDialog<SetStateAction>(
                    context: context,
                    builder: (_) => const _DeviceActionDialog(),
                  );
                  if (action != null) setState(() => _actions.add(action));
                },
              ),
              if (scenes.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Scene'),
                  onPressed: () async {
                    final sceneId = await showDialog<String>(
                      context: context,
                      builder: (context) => SimpleDialog(
                        title: const Text('Run scene'),
                        children: [
                          for (final s in scenes)
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, s.id),
                              child: Text(s.name),
                            ),
                        ],
                      ),
                    );
                    if (sceneId != null) {
                      setState(() =>
                          _actions.add(RunSceneAction(sceneId: sceneId)));
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceActionDialog extends ConsumerStatefulWidget {
  const _DeviceActionDialog();

  @override
  ConsumerState<_DeviceActionDialog> createState() =>
      _DeviceActionDialogState();
}

class _DeviceActionDialogState extends ConsumerState<_DeviceActionDialog> {
  String? _deviceId;
  String? _capability;
  bool _boolValue = true;
  final _numCtrl = TextEditingController();

  @override
  void dispose() {
    _numCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref
        .watch(devicesProvider)
        .where((d) => d.capabilities.any((c) => sceneValueFor(c) != null))
        .toList();
    final device = devices.where((d) => d.id == _deviceId).firstOrNull;
    final isBool = _capability == CapabilityType.powerSwitch;

    return AlertDialog(
      title: const Text('Device action'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _deviceId,
            decoration: const InputDecoration(
                labelText: 'Device', border: OutlineInputBorder()),
            items: [
              for (final d in devices)
                DropdownMenuItem(value: d.id, child: Text(d.name)),
            ],
            onChanged: (v) => setState(() {
              _deviceId = v;
              _capability = null;
            }),
          ),
          const SizedBox(height: 12),
          if (device != null)
            DropdownButtonFormField<String>(
              initialValue: _capability,
              decoration: const InputDecoration(
                  labelText: 'Capability', border: OutlineInputBorder()),
              items: [
                for (final c in device.capabilities)
                  if (sceneValueFor(c) != null)
                    DropdownMenuItem(value: c.type, child: Text(c.type)),
              ],
              onChanged: (v) => setState(() => _capability = v),
            ),
          const SizedBox(height: 12),
          if (_capability != null)
            isBool
                ? SwitchListTile(
                    title: Text(_boolValue ? 'Turn on' : 'Turn off'),
                    value: _boolValue,
                    onChanged: (v) => setState(() => _boolValue = v),
                  )
                : TextField(
                    controller: _numCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Value', border: OutlineInputBorder()),
                  ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _deviceId == null || _capability == null
              ? null
              : () => Navigator.pop(
                    context,
                    SetStateAction(
                      deviceId: _deviceId!,
                      capabilityType: _capability!,
                      value: isBool
                          ? _boolValue
                          : num.tryParse(_numCtrl.text) ?? 0,
                    ),
                  ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
