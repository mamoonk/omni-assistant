# Nexus Bridge

Standalone companion service for the Home Nexus app. Hosts the Nexus
WebSocket protocol, orchestrates radio managers, persists devices in BoltDB,
and advertises itself over mDNS (`_nexus-bridge._tcp`).

## Run

```sh
# no hardware — simulated Zigbee radio (joins demo devices on permit_join)
go run . -demo

# real Zigbee via Zigbee2MQTT, bridge-managed process
go run . -zigbee -z2m-cmd "node /opt/zigbee2mqtt/index.js"

# real Zigbee via an externally managed zigbee2mqtt
go run . -zigbee
```

In the app: Settings → Nexus Bridge → *Search network* (or enter the host)
→ Connect → **+** to start the inclusion wizard.

## Zigbee2MQTT wiring

The bridge embeds its own MQTT broker (default `:1884`) — no Mosquitto
needed. Point zigbee2mqtt at it in `configuration.yaml`:

```yaml
mqtt:
  server: mqtt://<bridge-host>:1884
  base_topic: zigbee2mqtt
```

With `-z2m-cmd`, the bridge supervises the process (restart with capped
backoff). Prerequisite: Node.js and a zigbee2mqtt checkout on the host.

## Flags

| Flag | Default | Purpose |
|---|---|---|
| `-port` | 8927 | WebSocket/HTTP listen port |
| `-name` | Nexus Bridge | mDNS-advertised name |
| `-data` | OS config dir | BoltDB location |
| `-demo` | off | simulated Zigbee radio |
| `-zigbee` | off | Zigbee2MQTT manager + embedded broker |
| `-mqtt-listen` | :1884 | embedded broker address |
| `-mqtt-base` | zigbee2mqtt | z2m base topic |
| `-z2m-cmd` | (empty) | command to launch & supervise z2m |
| `-no-mdns` | off | disable mDNS advertisement |

## Protocol

See `internal/protocol`. Envelopes: `command` (app→bridge, correlated by
`id`), `result`, `event`. Domains: `bridge` (info), `device` (list, execute),
`<radio>` (permit_join). Devices serialize in the same JSON shape as the
app's `unification` package.

## Cross-compile

`powershell -File ../scripts/build-bridge.ps1` → `dist/` binaries for
linux/arm64 (Raspberry Pi), linux/amd64, darwin/arm64, windows/amd64.

## Status

- ✅ demo manager, Zigbee2MQTT manager (embedded broker, supervisor)
- ⏳ Z-Wave JS UI manager — deferred until test hardware is available
