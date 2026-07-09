import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store.dart';
import '../state/ha_connection.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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

    return Scaffold(
      appBar: AppBar(title: const Text('Home Assistant')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusBanner(conn: conn),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: Text(busy ? 'Connecting…' : 'Connect'),
            onPressed: busy
                ? null
                : () {
                    if (!_formKey.currentState!.validate()) return;
                    ref.read(haConnectionProvider.notifier).connect(HaConfig(
                          url: _urlCtrl.text.trim(),
                          token: _tokenCtrl.text.trim(),
                        ));
                  },
          ),
          if (conn.status == HaStatus.connected ||
              conn.status == HaStatus.reconnecting) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              onPressed: () =>
                  ref.read(haConnectionProvider.notifier).disconnect(),
            ),
          ],
          if (conn.config != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Forget connection & clear cache'),
              onPressed: () => ref
                  .read(haConnectionProvider.notifier)
                  .disconnect(forget: true),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final HaConnectionState conn;
  const _StatusBanner({required this.conn});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (conn.status) {
      HaStatus.connected => (Icons.cloud_done, 'Connected', scheme.primary),
      HaStatus.connecting => (Icons.cloud_sync, 'Connecting…', scheme.tertiary),
      HaStatus.reconnecting => (
          Icons.cloud_sync,
          'Reconnecting (attempt ${conn.attempt})…',
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
            if (conn.error != null) ...[
              const SizedBox(height: 6),
              Text(
                conn.error!,
                style: TextStyle(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
