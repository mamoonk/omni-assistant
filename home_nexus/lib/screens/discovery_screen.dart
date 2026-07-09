import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store.dart';
import '../services/network_discovery.dart';
import '../state/bridge_connection.dart';
import '../state/ha_connection.dart';
import '../state/mqtt_connection.dart';
import 'manual_ip_screen.dart';

/// Auto-discovery: sweeps the LAN (mDNS + port scan) and turns findings
/// into one-tap setup flows — the system figures out what's out there.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  double _progress = 0;
  bool _scanning = false;
  List<DiscoveredIntegration> _results = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _progress = 0;
      _results = const [];
    });
    final results = await discoverIntegrations(
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto-discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan again',
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(
                    _progress < 0.15
                        ? 'Listening for devices announcing themselves…'
                        : 'Scanning your network…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Expanded(
            child: !_scanning && _results.isEmpty
                ? const Center(
                    child: Text(
                        'Nothing found — hubs and devices can still be\n'
                        'added manually from Settings',
                        textAlign: TextAlign.center),
                  )
                : ListView(
                    children: [
                      for (final d in _results)
                        _IntegrationTile(
                          integration: d,
                          onSetup: () => _setUp(d),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _setUp(DiscoveredIntegration d) async {
    switch (d.kind) {
      case IntegrationKind.homeAssistant:
        final token = await _promptSecret(
          title: 'Connect ${d.name}',
          label: 'Long-lived access token',
          helper: 'HA profile → Security → Long-lived access tokens',
        );
        if (token == null || token.isEmpty) return;
        await ref.read(haConnectionProvider.notifier).connect(
            HaConfig(url: 'http://${d.host}:${d.port}', token: token));
        _report('Connecting to Home Assistant…');

      case IntegrationKind.mqttBroker:
        await ref
            .read(mqttConnectionProvider.notifier)
            .connect(MqttConfig(host: d.host, port: d.port));
        _report('Connecting to MQTT broker…');

      case IntegrationKind.nexusBridge:
        final token = await _promptSecret(
          title: 'Pair with ${d.name}',
          label: 'Pairing token',
          helper: 'Printed in the bridge log on startup',
        );
        if (token == null) return;
        await ref.read(bridgeConnectionProvider.notifier).connect(
            BridgeConfig(host: d.host, port: d.port, token: token));
        _report('Connecting to Nexus Bridge…');

      case IntegrationKind.httpDevice:
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ManualIpScreen(initialIp: d.host)));
    }
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _promptSecret({
    required String title,
    required String label,
    required String helper,
  }) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _IntegrationTile extends StatelessWidget {
  final DiscoveredIntegration integration;
  final VoidCallback onSetup;

  const _IntegrationTile({required this.integration, required this.onSetup});

  @override
  Widget build(BuildContext context) {
    final (icon, subtitle) = switch (integration.kind) {
      IntegrationKind.homeAssistant => (
          Icons.home_work_outlined,
          'Home Assistant hub — import every entity'
        ),
      IntegrationKind.mqttBroker => (
          Icons.lan_outlined,
          'MQTT broker — Zigbee2MQTT devices'
        ),
      IntegrationKind.nexusBridge => (
          Icons.hub_outlined,
          'Nexus Bridge — Zigbee & Matter commissioning'
        ),
      IntegrationKind.httpDevice => (
          Icons.language,
          'Network device — add as HTTP switch/light/sensor'
        ),
    };

    return ListTile(
      leading: Icon(icon),
      title: Text(integration.name),
      subtitle: Text(
          '$subtitle\n${integration.host}:${integration.port} · '
          '${integration.source == 'mdns' ? 'announced itself' : 'found by scan'}'),
      isThreeLine: true,
      trailing: FilledButton.tonal(
        onPressed: onSetup,
        child: const Text('Set up'),
      ),
    );
  }
}
