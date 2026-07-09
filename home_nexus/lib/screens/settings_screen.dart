import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_bridge_adapter/nexus_bridge_adapter.dart'
    show DiscoveredBridge, discoverBridges;

import '../services/local_store.dart';
import '../state/bridge_connection.dart';
import '../state/ha_connection.dart';
import '../state/mqtt_connection.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _AppearanceSection(),
          SizedBox(height: 24),
          _LocationSection(),
          SizedBox(height: 24),
          _BridgeSection(),
          SizedBox(height: 24),
          _HaSection(),
          SizedBox(height: 24),
          _MqttSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto)),
            ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode)),
            ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode)),
          ],
          selected: {mode},
          onSelectionChanged: (s) async {
            ref.read(themeModeProvider.notifier).state = s.first;
            final store = await ref.read(localStoreProvider.future);
            await store.saveThemeMode(s.first.name);
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Home location (sun-based automations)
// ---------------------------------------------------------------------------

class _LocationSection extends ConsumerStatefulWidget {
  const _LocationSection();

  @override
  ConsumerState<_LocationSection> createState() => _LocationSectionState();
}

class _LocationSectionState extends ConsumerState<_LocationSection> {
  late final TextEditingController _latCtrl;
  late final TextEditingController _lonCtrl;

  @override
  void initState() {
    super.initState();
    final location = ref.read(homeLocationProvider);
    _latCtrl = TextEditingController(text: location?.lat.toString() ?? '');
    _lonCtrl = TextEditingController(text: location?.lon.toString() ?? '');
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid coordinates')));
      return;
    }
    ref.read(homeLocationProvider.notifier).state = (lat: lat, lon: lon);
    final store = await ref.read(localStoreProvider.future);
    await store.saveHomeLocation(lat, lon);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Home location saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Home location', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Used for sunrise/sunset automations',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _latCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'Latitude', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lonCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'Longitude', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Nexus Bridge
// ---------------------------------------------------------------------------

class _BridgeSection extends ConsumerStatefulWidget {
  const _BridgeSection();

  @override
  ConsumerState<_BridgeSection> createState() => _BridgeSectionState();
}

class _BridgeSectionState extends ConsumerState<_BridgeSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _tokenCtrl;
  bool _scanning = false;

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final bridges = await discoverBridges();
    if (!mounted) return;
    setState(() => _scanning = false);

    if (bridges.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No bridges found — enter the host manually')));
      return;
    }
    if (bridges.length == 1) {
      _apply(bridges.single);
      return;
    }
    final choice = await showDialog<DiscoveredBridge>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Bridges found'),
        children: [
          for (final b in bridges)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, b),
              child: Text('${b.name} — ${b.host}:${b.port}'),
            ),
        ],
      ),
    );
    if (choice != null) _apply(choice);
  }

  void _apply(DiscoveredBridge bridge) {
    setState(() {
      _hostCtrl.text = bridge.host;
      _portCtrl.text = '${bridge.port}';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(bridge.authRequired
          ? 'Found "${bridge.name}" v${bridge.version} — pairing token '
              'required (see the bridge log)'
          : 'Found "${bridge.name}" v${bridge.version} — no token needed'),
    ));
  }

  @override
  void initState() {
    super.initState();
    final config = ref.read(bridgeConnectionProvider).config;
    _hostCtrl = TextEditingController(text: config?.host ?? '');
    _portCtrl = TextEditingController(text: '${config?.port ?? 8927}');
    _tokenCtrl = TextEditingController(text: config?.token ?? '');
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(bridgeConnectionProvider);
    final busy = conn.status == HaStatus.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nexus Bridge', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          conn.info != null
              ? '${conn.info!.name} v${conn.info!.version} — '
                  '${conn.info!.protocols.join(', ')}'
              : 'Companion service for direct Zigbee/Z-Wave control',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _StatusBanner(
            status: conn.status, error: conn.error, attempt: conn.attempt),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: _scanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.radar),
          label: Text(_scanning ? 'Searching…' : 'Search network'),
          onPressed: _scanning ? null : _scan,
        ),
        const SizedBox(height: 12),
        Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        hintText: '192.168.1.20',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Host required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _portCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          int.tryParse(v ?? '') == null ? 'Invalid' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pairing token',
                  helperText: 'Printed in the bridge log on startup',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                maxLines: 1,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ConnectButtons(
          busy: busy,
          connected: conn.status == HaStatus.connected ||
              conn.status == HaStatus.reconnecting,
          hasConfig: conn.config != null,
          onConnect: () {
            if (!_formKey.currentState!.validate()) return;
            ref.read(bridgeConnectionProvider.notifier).connect(BridgeConfig(
                  host: _hostCtrl.text.trim(),
                  port: int.parse(_portCtrl.text.trim()),
                  token: _tokenCtrl.text.trim(),
                ));
          },
          onDisconnect: () =>
              ref.read(bridgeConnectionProvider.notifier).disconnect(),
          onForget: () => ref
              .read(bridgeConnectionProvider.notifier)
              .disconnect(forget: true),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Home Assistant
// ---------------------------------------------------------------------------

class _HaSection extends ConsumerStatefulWidget {
  const _HaSection();

  @override
  ConsumerState<_HaSection> createState() => _HaSectionState();
}

class _HaSectionState extends ConsumerState<_HaSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;

  @override
  void initState() {
    super.initState();
    final config = ref.read(haConnectionProvider).config;
    _urlCtrl = TextEditingController(
        text: config?.url ?? 'http://homeassistant.local:8123');
    _tokenCtrl = TextEditingController(text: config?.token ?? '');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(haConnectionProvider);
    final busy = conn.status == HaStatus.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Home Assistant',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _StatusBanner(
            status: conn.status, error: conn.error, attempt: conn.attempt),
        const SizedBox(height: 12),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'http://homeassistant.local:8123',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  final uri = Uri.tryParse(v ?? '');
                  if (uri == null ||
                      !(uri.isScheme('http') || uri.isScheme('https')) ||
                      uri.host.isEmpty) {
                    return 'Enter a valid http(s) URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Long-lived access token',
                  helperText:
                      'HA profile → Security → Long-lived access tokens',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                maxLines: 1,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Token required' : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ConnectButtons(
          busy: busy,
          connected: conn.status == HaStatus.connected ||
              conn.status == HaStatus.reconnecting,
          hasConfig: conn.config != null,
          onConnect: () {
            if (!_formKey.currentState!.validate()) return;
            ref.read(haConnectionProvider.notifier).connect(HaConfig(
                  url: _urlCtrl.text.trim(),
                  token: _tokenCtrl.text.trim(),
                ));
          },
          onDisconnect: () =>
              ref.read(haConnectionProvider.notifier).disconnect(),
          onForget: () => ref
              .read(haConnectionProvider.notifier)
              .disconnect(forget: true),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// MQTT (Zigbee2MQTT / ZWave2MQTT broker)
// ---------------------------------------------------------------------------

class _MqttSection extends ConsumerStatefulWidget {
  const _MqttSection();

  @override
  ConsumerState<_MqttSection> createState() => _MqttSectionState();
}

class _MqttSectionState extends ConsumerState<_MqttSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _topicCtrl;

  @override
  void initState() {
    super.initState();
    final config = ref.read(mqttConnectionProvider).config;
    _hostCtrl = TextEditingController(text: config?.host ?? '');
    _portCtrl = TextEditingController(text: '${config?.port ?? 1883}');
    _userCtrl = TextEditingController(text: config?.username ?? '');
    _passCtrl = TextEditingController(text: config?.password ?? '');
    _topicCtrl =
        TextEditingController(text: config?.baseTopic ?? 'zigbee2mqtt');
  }

  @override
  void dispose() {
    for (final c in [_hostCtrl, _portCtrl, _userCtrl, _passCtrl, _topicCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(mqttConnectionProvider);
    final busy = conn.status == HaStatus.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('MQTT broker (Zigbee2MQTT)',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _StatusBanner(
            status: conn.status, error: conn.error, attempt: conn.attempt),
        const SizedBox(height: 12),
        Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        hintText: '192.168.1.10',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Host required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _portCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          int.tryParse(v ?? '') == null ? 'Invalid' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _passCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Password (optional)',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _topicCtrl,
                decoration: const InputDecoration(
                  labelText: 'Base topic',
                  helperText: 'zigbee2mqtt unless renamed in its config',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Base topic required'
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ConnectButtons(
          busy: busy,
          connected: conn.status == HaStatus.connected ||
              conn.status == HaStatus.reconnecting,
          hasConfig: conn.config != null,
          onConnect: () {
            if (!_formKey.currentState!.validate()) return;
            ref.read(mqttConnectionProvider.notifier).connect(MqttConfig(
                  host: _hostCtrl.text.trim(),
                  port: int.parse(_portCtrl.text.trim()),
                  username: _userCtrl.text.trim().isEmpty
                      ? null
                      : _userCtrl.text.trim(),
                  password: _passCtrl.text.trim().isEmpty
                      ? null
                      : _passCtrl.text.trim(),
                  baseTopic: _topicCtrl.text.trim(),
                ));
          },
          onDisconnect: () =>
              ref.read(mqttConnectionProvider.notifier).disconnect(),
          onForget: () => ref
              .read(mqttConnectionProvider.notifier)
              .disconnect(forget: true),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

class _ConnectButtons extends StatelessWidget {
  final bool busy;
  final bool connected;
  final bool hasConfig;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onForget;

  const _ConnectButtons({
    required this.busy,
    required this.connected,
    required this.hasConfig,
    required this.onConnect,
    required this.onDisconnect,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link),
          label: Text(busy ? 'Connecting…' : 'Connect'),
          onPressed: busy ? null : onConnect,
        ),
        if (connected) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.link_off),
            label: const Text('Disconnect'),
            onPressed: onDisconnect,
          ),
        ],
        if (hasConfig) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Forget connection'),
            onPressed: onForget,
          ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final HaStatus status;
  final String? error;
  final int attempt;
  const _StatusBanner(
      {required this.status, this.error, this.attempt = 0});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status) {
      HaStatus.connected => (Icons.cloud_done, 'Connected', scheme.primary),
      HaStatus.connecting => (Icons.cloud_sync, 'Connecting…', scheme.tertiary),
      HaStatus.reconnecting => (
          Icons.cloud_sync,
          'Reconnecting (attempt $attempt)…',
          scheme.tertiary
        ),
      HaStatus.error => (Icons.cloud_off, 'Connection failed', scheme.error),
      HaStatus.disconnected => (
          Icons.cloud_off,
          'Not connected',
          scheme.outline
        ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(label, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
