import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../state/automations_provider.dart';
import '../state/device_providers.dart';
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
                    child: SwitchListTile(
                      title: Text(automation.name),
                      subtitle: Text(_describe(ref, automation)),
                      value: automation.enabled,
                      onChanged: (v) => ref
                          .read(automationsProvider.notifier)
                          .toggle(automation.id, v),
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
    };
    return '$when → ${automation.actions.length} action(s)';
  }
}

class AutomationEditorScreen extends ConsumerStatefulWidget {
  const AutomationEditorScreen({super.key});

  @override
  ConsumerState<AutomationEditorScreen> createState() =>
      _AutomationEditorScreenState();
}

class _AutomationEditorScreenState
    extends ConsumerState<AutomationEditorScreen> {
  final _nameCtrl = TextEditingController();

  // trigger
  bool _timeTrigger = false;
  String? _triggerDeviceId;
  String? _triggerCapability;
  String _triggerOp = '==';
  final _triggerValueCtrl = TextEditingController();
  bool _triggerBoolValue = true;
  TimeOfDay _triggerTime = const TimeOfDay(hour: 8, minute: 0);

  // condition
  bool _useTimeRange = false;
  TimeOfDay _rangeStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _rangeEnd = const TimeOfDay(hour: 6, minute: 0);

  // actions
  final _actions = <AutomationAction>[];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _triggerValueCtrl.dispose();
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
    if (_timeTrigger) {
      trigger =
          TimeTrigger(hour: _triggerTime.hour, minute: _triggerTime.minute);
    } else {
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
      id: 'auto_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
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
        title: const Text('New automation'),
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
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Device state')),
              ButtonSegment(value: true, label: Text('Time')),
            ],
            selected: {_timeTrigger},
            onSelectionChanged: (s) => setState(() => _timeTrigger = s.first),
          ),
          const SizedBox(height: 12),
          if (_timeTrigger)
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
          else ...[
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
