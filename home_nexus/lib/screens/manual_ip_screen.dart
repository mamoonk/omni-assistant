import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unification/unification.dart';

import '../services/manual_ip.dart';
import '../state/manual_ip_provider.dart';

/// "Generic IP Device" creator (§6.1): capability template + URL templates.
class ManualIpScreen extends ConsumerStatefulWidget {
  /// Pre-fills the IP field (used by auto-discovery).
  final String? initialIp;
  const ManualIpScreen({super.key, this.initialIp});

  @override
  ConsumerState<ManualIpScreen> createState() => _ManualIpScreenState();
}

class _ManualIpScreenState extends ConsumerState<ManualIpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  late final _ipCtrl = TextEditingController(text: widget.initialIp ?? '');
  final _onCtrl = TextEditingController(text: 'http://{ip}/relay/0?turn=on');
  final _offCtrl = TextEditingController(text: 'http://{ip}/relay/0?turn=off');
  final _brightnessCtrl =
      TextEditingController(text: 'http://{ip}/light/0?brightness={value}');
  final _pollCtrl = TextEditingController(text: 'http://{ip}/status');
  final _pathCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: '°C');
  ManualTemplate _template = ManualTemplate.switchDevice;
  String _sensorType = CapabilityType.currentTemperature;

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _roomCtrl, _ipCtrl, _onCtrl, _offCtrl,
      _brightnessCtrl, _pollCtrl, _pathCtrl, _unitCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final urls = <String, String>{
      if (_template != ManualTemplate.sensor) ...{
        'on': _onCtrl.text.trim(),
        'off': _offCtrl.text.trim(),
      },
      if (_template == ManualTemplate.dimmer)
        'brightness': _brightnessCtrl.text.trim(),
      if (_template == ManualTemplate.sensor) 'poll': _pollCtrl.text.trim(),
    };
    final config = ManualIpConfig(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim(),
      roomId:
          _roomCtrl.text.trim().isEmpty ? 'unassigned' : _roomCtrl.text.trim(),
      template: _template,
      ip: _ipCtrl.text.trim(),
      urls: urls,
      valuePath: _pathCtrl.text.trim(),
      sensorType: _sensorType,
      unit: _unitCtrl.text.trim(),
    );
    await ref.read(manualIpProvider.notifier).add(config);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generic IP device'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _roomCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Room', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _ipCtrl,
                    decoration: const InputDecoration(
                        labelText: 'IP address',
                        hintText: '192.168.1.30',
                        border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<ManualTemplate>(
              segments: const [
                ButtonSegment(
                    value: ManualTemplate.switchDevice, label: Text('Switch')),
                ButtonSegment(
                    value: ManualTemplate.dimmer, label: Text('Light')),
                ButtonSegment(
                    value: ManualTemplate.sensor, label: Text('Sensor')),
              ],
              selected: {_template},
              onSelectionChanged: (s) => setState(() => _template = s.first),
            ),
            const SizedBox(height: 16),
            if (_template != ManualTemplate.sensor) ...[
              TextFormField(
                controller: _onCtrl,
                decoration: const InputDecoration(
                    labelText: 'ON URL ({ip} substituted)',
                    border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _offCtrl,
                decoration: const InputDecoration(
                    labelText: 'OFF URL', border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
            if (_template == ManualTemplate.dimmer) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _brightnessCtrl,
                decoration: const InputDecoration(
                    labelText: 'Brightness URL ({value} = 0-100)',
                    border: OutlineInputBorder()),
              ),
            ],
            if (_template == ManualTemplate.sensor) ...[
              TextFormField(
                controller: _pollCtrl,
                decoration: const InputDecoration(
                    labelText: 'Poll URL (JSON response)',
                    border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pathCtrl,
                decoration: const InputDecoration(
                    labelText: 'Value path, e.g. sensors.0.temperature',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sensorType,
                      decoration: const InputDecoration(
                          labelText: 'Sensor type',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: CapabilityType.currentTemperature,
                            child: Text('Temperature')),
                        DropdownMenuItem(
                            value: CapabilityType.humidity,
                            child: Text('Humidity')),
                        DropdownMenuItem(
                            value: CapabilityType.illuminance,
                            child: Text('Illuminance')),
                      ],
                      onChanged: (v) => setState(() => _sensorType = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      controller: _unitCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Unit', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
