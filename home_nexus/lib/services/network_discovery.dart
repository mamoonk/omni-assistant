import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

/// What the auto-discovery sweep can identify on the LAN and how the app
/// should set it up.
enum IntegrationKind {
  homeAssistant, // 8123 / _home-assistant._tcp
  mqttBroker, // 1883
  nexusBridge, // 8927 / _nexus-bridge._tcp
  httpDevice, // Shelly/WLED/ESPHome-style mDNS gadgets -> manual IP flow
}

class DiscoveredIntegration {
  final IntegrationKind kind;
  final String host;
  final int port;
  final String name;
  final String source; // 'mdns' | 'scan'

  const DiscoveredIntegration({
    required this.kind,
    required this.host,
    required this.port,
    required this.name,
    required this.source,
  });

  String get key => '${kind.name}@$host:$port';
}

/// Maps a responding TCP port to what likely lives behind it.
IntegrationKind? classifyPort(int port) => switch (port) {
      8123 => IntegrationKind.homeAssistant,
      1883 => IntegrationKind.mqttBroker,
      8927 => IntegrationKind.nexusBridge,
      _ => null,
    };

const scanPorts = [8123, 1883, 8927];

/// mDNS service types worth sweeping, mapped to integration kinds.
const mdnsServices = <String, IntegrationKind>{
  '_home-assistant._tcp.local': IntegrationKind.homeAssistant,
  '_nexus-bridge._tcp.local': IntegrationKind.nexusBridge,
  '_mqtt._tcp.local': IntegrationKind.mqttBroker,
  '_shelly._tcp.local': IntegrationKind.httpDevice,
  '_wled._tcp.local': IntegrationKind.httpDevice,
  '_esphomelib._tcp.local': IntegrationKind.httpDevice,
};

/// '192.168.1.37' -> '192.168.1'
String subnetBase(String ip) {
  final parts = ip.split('.');
  return parts.take(3).join('.');
}

/// Local IPv4s that look like LAN addresses.
Future<List<String>> localIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLinkLocal: false);
    return [
      for (final iface in interfaces)
        for (final addr in iface.addresses)
          if (!addr.isLoopback) addr.address,
    ];
  } catch (_) {
    return const [];
  }
}

/// True when [host]:[port] accepts a TCP connection within [timeout].
Future<bool> probePort(String host, int port,
    {Duration timeout = const Duration(milliseconds: 350)}) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Full sweep: mDNS service browse + TCP port scan of the local /24.
/// [onProgress] gets 0..1. Results are deduped (mDNS wins over scan).
Future<List<DiscoveredIntegration>> discoverIntegrations({
  void Function(double progress)? onProgress,
  Duration mdnsWindow = const Duration(seconds: 3),
}) async {
  final found = <String, DiscoveredIntegration>{};

  void add(DiscoveredIntegration d) => found.putIfAbsent(d.key, () => d);

  // ---- pass 1: mDNS (precise names, instant when supported) ----
  try {
    final client = MDnsClient();
    await client.start();
    await Future.wait([
      for (final entry in mdnsServices.entries)
        _browseService(client, entry.key, entry.value, add)
            .timeout(mdnsWindow, onTimeout: () {}),
    ]);
    client.stop();
  } catch (_) {
    // multicast unavailable (VPN, emulator): the port scan still runs
  }
  onProgress?.call(0.15);

  // ---- pass 2: TCP sweep of each local /24 ----
  final ips = await localIPv4Addresses();
  final bases = {for (final ip in ips) subnetBase(ip)};
  final targets = <(String, int)>[
    for (final base in bases)
      for (var host = 1; host <= 254; host++)
        for (final port in scanPorts) ('$base.$host', port),
  ];

  var done = 0;
  const concurrency = 64;
  for (var i = 0; i < targets.length; i += concurrency) {
    final chunk = targets.skip(i).take(concurrency);
    await Future.wait([
      for (final (host, port) in chunk)
        probePort(host, port).then((open) {
          if (open) {
            final kind = classifyPort(port);
            if (kind != null) {
              add(DiscoveredIntegration(
                kind: kind,
                host: host,
                port: port,
                name: _defaultName(kind, host),
                source: 'scan',
              ));
            }
          }
        }),
    ]);
    done += chunk.length;
    onProgress?.call(0.15 + 0.85 * done / targets.length);
  }

  onProgress?.call(1);
  final results = found.values.toList()
    ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return results;
}

Future<void> _browseService(
  MDnsClient client,
  String service,
  IntegrationKind kind,
  void Function(DiscoveredIntegration) add,
) async {
  await for (final ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(service))) {
    await for (final srv in client
        .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
        .timeout(const Duration(seconds: 2), onTimeout: (s) => s.close())) {
      var host = srv.target;
      await for (final ip in client
          .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target))
          .timeout(const Duration(seconds: 2), onTimeout: (s) => s.close())) {
        host = ip.address.address;
        break;
      }
      final name = ptr.domainName.replaceAll('.$service', '');
      add(DiscoveredIntegration(
        kind: kind,
        host: host,
        port: srv.port,
        name: name.isEmpty ? _defaultName(kind, host) : name,
        source: 'mdns',
      ));
    }
  }
}

String _defaultName(IntegrationKind kind, String host) => switch (kind) {
      IntegrationKind.homeAssistant => 'Home Assistant ($host)',
      IntegrationKind.mqttBroker => 'MQTT broker ($host)',
      IntegrationKind.nexusBridge => 'Nexus Bridge ($host)',
      IntegrationKind.httpDevice => 'Network device ($host)',
    };
