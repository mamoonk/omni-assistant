import 'package:multicast_dns/multicast_dns.dart';

const _serviceType = '_nexus-bridge._tcp.local';

class DiscoveredBridge {
  final String name;
  final String host;
  final int port;
  final String version;
  final bool authRequired;
  final String instanceId;
  const DiscoveredBridge({
    required this.name,
    required this.host,
    required this.port,
    this.version = '?',
    this.authRequired = true, // safe default: assume a token is needed
    this.instanceId = '',
  });
}

/// mDNS scan for bridges advertising `_nexus-bridge._tcp`. Best-effort:
/// returns whatever answered within [timeout]; empty on platforms where
/// multicast is blocked (the manual host field remains the fallback).
Future<List<DiscoveredBridge>> discoverBridges(
    {Duration timeout = const Duration(seconds: 4)}) async {
  final client = MDnsClient();
  final found = <String, DiscoveredBridge>{};
  try {
    await client.start();
    await for (final ptr in client
        .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceType))
        .timeout(timeout, onTimeout: (sink) => sink.close())) {
      // TXT: version / auth / id — lets the UI say whether a pairing
      // token is needed before the user even connects
      var version = '?';
      var authRequired = true;
      var instanceId = '';
      await for (final txt in client
          .lookup<TxtResourceRecord>(
              ResourceRecordQuery.text(ptr.domainName))
          .timeout(const Duration(seconds: 2),
              onTimeout: (sink) => sink.close())) {
        for (final line in txt.text.split('\n')) {
          final eq = line.indexOf('=');
          if (eq <= 0) continue;
          final key = line.substring(0, eq);
          final value = line.substring(eq + 1).trim();
          switch (key) {
            case 'version':
              version = value;
            case 'auth':
              authRequired = value != 'open';
            case 'id':
              instanceId = value;
          }
        }
      }

      await for (final srv in client
          .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName))
          .timeout(const Duration(seconds: 2),
              onTimeout: (sink) => sink.close())) {
        var host = srv.target;
        // prefer a resolved IPv4 over the .local hostname
        await for (final ip in client
            .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target))
            .timeout(const Duration(seconds: 2),
                onTimeout: (sink) => sink.close())) {
          host = ip.address.address;
          break;
        }
        final name = ptr.domainName
            .replaceAll('.$_serviceType', '')
            .replaceAll('._nexus-bridge._tcp.local', '');
        found['$host:${srv.port}'] = DiscoveredBridge(
          name: name,
          host: host,
          port: srv.port,
          version: version,
          authRequired: authRequired,
          instanceId: instanceId,
        );
      }
    }
  } catch (_) {
    // multicast unavailable (emulator, VPN, some Windows setups) — no results
  } finally {
    client.stop();
  }
  return found.values.toList();
}
