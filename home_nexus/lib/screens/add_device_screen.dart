import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_bridge_adapter/nexus_bridge_adapter.dart';
import 'package:unification/unification.dart';

import '../state/bridge_connection.dart';
import '../state/device_providers.dart';
import '../state/ha_connection.dart' show HaStatus, localStoreProvider;

const _joinWindowSeconds = 60;

/// Guided device inclusion via the Nexus Bridge (§5.4): pick protocol,
/// open the network, watch join -> interview progress, then name the device.
class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

enum _Step { pickProtocol, searching, review }

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  _Step _step = _Step.pickProtocol;
  String _protocol = 'zigbee';
  int _secondsLeft = _joinWindowSeconds;
  bool _interviewing = false;
  final _found = <UniversalDevice>[];
  final _matterCodeCtrl = TextEditingController();
  Timer? _countdown;
  StreamSubscription? _joinSub;

  @override
  void dispose() {
    _matterCodeCtrl.dispose();
    _countdown?.cancel();
    _joinSub?.cancel();
    super.dispose();
  }

  Future<void> _startSearch(NexusBridgeAdapter adapter) async {
    setState(() {
      _step = _Step.searching;
      _secondsLeft = _joinWindowSeconds;
      _interviewing = false;
      _found.clear();
    });

    _joinSub = adapter.joinEvents.listen((event) {
      if (!mounted) return;
      switch (event) {
        case DeviceJoined():
          setState(() => _interviewing = true);
        case DeviceInterviewed(:final device):
          setState(() {
            _interviewing = false;
            _found.add(device);
          });
          // matter commissions one device per code; done as soon as it lands
          if (_protocol == 'matter') _finishSearch();
        case PermitJoinChanged(:final enabled):
          if (!enabled && _found.isNotEmpty) _finishSearch();
      }
    });

    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) _finishSearch();
    });

    try {
      if (_protocol == 'matter') {
        await adapter.commission(_matterCodeCtrl.text.trim());
      } else {
        await adapter.permitJoin(
            protocol: _protocol, duration: _joinWindowSeconds);
      }
    } catch (e) {
      _countdown?.cancel();
      _joinSub?.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to start: $e')));
      setState(() => _step = _Step.pickProtocol);
    }
  }

  void _finishSearch() {
    _countdown?.cancel();
    _joinSub?.cancel();
    if (!mounted) return;
    setState(
        () => _step = _found.isEmpty ? _Step.pickProtocol : _Step.review);
    if (_found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No devices found — try again')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(bridgeConnectionProvider);
    final adapter = ref.read(bridgeConnectionProvider.notifier).adapter;

    if (conn.status != HaStatus.connected || adapter == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add device')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hub_outlined, size: 48),
              const SizedBox(height: 12),
              const Text('Connect a Nexus Bridge first'),
              const SizedBox(height: 4),
              Text(
                'Settings → Nexus Bridge',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add device')),
      body: switch (_step) {
        _Step.pickProtocol => _ProtocolPicker(
            protocols: conn.info?.protocols ?? const ['zigbee'],
            selected: _protocol,
            matterCodeCtrl: _matterCodeCtrl,
            onSelect: (p) => setState(() => _protocol = p),
            onStart: () {
              if (_protocol == 'matter' &&
                  !_matterCodeCtrl.text.trim().startsWith('MT:')) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Enter the QR payload starting with MT:')));
                return;
              }
              _startSearch(adapter);
            },
          ),
        _Step.searching => _SearchingView(
            secondsLeft: _secondsLeft,
            interviewing: _interviewing,
            foundCount: _found.length,
            onCancel: _finishSearch,
          ),
        _Step.review => _ReviewView(
            devices: _found,
            onDone: () => Navigator.of(context).pop(),
          ),
      },
    );
  }
}

class _ProtocolPicker extends StatelessWidget {
  final List<String> protocols;
  final String selected;
  final TextEditingController matterCodeCtrl;
  final ValueChanged<String> onSelect;
  final VoidCallback onStart;

  const _ProtocolPicker({
    required this.protocols,
    required this.selected,
    required this.matterCodeCtrl,
    required this.onSelect,
    required this.onStart,
  });

  static const _labels = {
    'zigbee': ('Zigbee', 'Put the device in pairing mode, then start the search'),
    'zwave': ('Z-Wave', 'Put the device in inclusion mode'),
    'matter': ('Matter', 'Enter the code under the QR on the device'),
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Radio', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (v) => onSelect(v!),
          child: Column(
            children: [
              for (final p in protocols)
                RadioListTile<String>(
                  title: Text(_labels[p]?.$1 ?? p),
                  subtitle: Text(_labels[p]?.$2 ?? ''),
                  value: p,
                ),
            ],
          ),
        ),
        if (selected == 'matter') ...[
          const SizedBox(height: 8),
          TextField(
            controller: matterCodeCtrl,
            decoration: const InputDecoration(
              labelText: 'Matter pairing code',
              hintText: 'MT:Y.K9042C00KA0648G00',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: Icon(selected == 'matter' ? Icons.qr_code : Icons.search),
          label: Text(selected == 'matter' ? 'Commission' : 'Start search'),
          onPressed: onStart,
        ),
      ],
    );
  }
}

class _SearchingView extends StatelessWidget {
  final int secondsLeft;
  final bool interviewing;
  final int foundCount;
  final VoidCallback onCancel;

  const _SearchingView({
    required this.secondsLeft,
    required this.interviewing,
    required this.foundCount,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: secondsLeft / _joinWindowSeconds,
                  strokeWidth: 6,
                ),
                Text('${secondsLeft}s',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            interviewing
                ? 'Device found — interviewing…'
                : foundCount > 0
                    ? '$foundCount device(s) ready — network still open'
                    : 'Network open — searching for devices…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onCancel, child: const Text('Stop')),
        ],
      ),
    );
  }
}

class _ReviewView extends ConsumerWidget {
  final List<UniversalDevice> devices;
  final VoidCallback onDone;

  const _ReviewView({required this.devices, required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Found ${devices.length} device(s)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final device in devices)
          _DeviceReviewTile(key: ValueKey(device.id), device: device),
        const SizedBox(height: 16),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}

/// Rename + room assignment applied locally (bridge devices arrive unnamed).
class _DeviceReviewTile extends ConsumerStatefulWidget {
  final UniversalDevice device;
  const _DeviceReviewTile({super.key, required this.device});

  @override
  ConsumerState<_DeviceReviewTile> createState() => _DeviceReviewTileState();
}

class _DeviceReviewTileState extends ConsumerState<_DeviceReviewTile> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.device.name);
  late final TextEditingController _roomCtrl =
      TextEditingController(text: widget.device.roomId);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final updated = UniversalDevice(
      id: widget.device.id,
      name: _nameCtrl.text.trim().isEmpty
          ? widget.device.name
          : _nameCtrl.text.trim(),
      manufacturer: widget.device.manufacturer,
      model: widget.device.model,
      origin: widget.device.origin,
      capabilities: widget.device.capabilities,
      roomId:
          _roomCtrl.text.trim().isEmpty ? 'unassigned' : _roomCtrl.text.trim(),
    );
    ref.read(devicesProvider.notifier).upsert(updated);
    final store = await ref.read(localStoreProvider.future);
    await store.saveDevices(ref.read(devicesProvider));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "${updated.name}"')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${device.manufacturer} ${device.model}',
                style: Theme.of(context).textTheme.bodySmall),
            Text(
              device.capabilities.map((c) => c.type).join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _roomCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Room',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _apply,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
