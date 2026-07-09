# Omni Assistant (Home Nexus)

One app that discovers, configures, and controls smart devices on any
protocol — with or without an existing hub.

| Component | Path | Stack |
|---|---|---|
| Mobile/desktop app | [home_nexus/](home_nexus) | Flutter + Riverpod |
| Core data model | [home_nexus/packages/unification](home_nexus/packages/unification) | pure Dart, zero deps |
| Home Assistant adapter | [home_nexus/packages/home_assistant_adapter](home_nexus/packages/home_assistant_adapter) | WebSocket |
| MQTT adapter (Zigbee2MQTT) | [home_nexus/packages/mqtt_adapter](home_nexus/packages/mqtt_adapter) | mqtt_client |
| Nexus Bridge adapter | [home_nexus/packages/nexus_bridge_adapter](home_nexus/packages/nexus_bridge_adapter) | WebSocket + mDNS |
| Nexus Bridge service | [bridge/](bridge) | Go, embedded MQTT broker, BoltDB |

## Quick start

```sh
# app
cd home_nexus && flutter run

# bridge (no hardware needed)
cd bridge && go run . -demo
```

Then in the app: Settings → connect Home Assistant, an MQTT broker, or the
Nexus Bridge. **+** opens the device-inclusion wizard (bridge required).

## Tests

```sh
cd home_nexus && flutter test                      # app
for p in packages/*; do (cd $p && dart test); done # adapter packages
cd bridge && go test ./...                         # bridge
```

## Roadmap

- [x] Phase 1 — HA adapter, auto-generated live dashboard, offline cache
- [x] Phase 2 — dashboard editor, scenes, direct MQTT (Zigbee2MQTT)
- [x] Phase 3 — Nexus Bridge: protocol, Zigbee2MQTT manager (embedded
      broker + supervised process), inclusion wizard, mDNS discovery
      (Z-Wave manager pending hardware)
- [x] Phase 4 — manual IP devices, automation composer, bridge automation
      runtime (rules run 24/7 on the bridge; app engine covers the rest)
- [x] Phase 5 — Matter commissioning (QR payload parser, simulated
      controller, chip-tool hook), energy dashboard, theme polish
- [ ] Hardware-gated backlog — Z-Wave JS UI manager, chip-tool attribute
      subscriptions, real-radio validation, store submission

## Matter & Thread

The bridge parses Matter QR payloads (`MT:...`) natively and commissions
via [chip-tool](https://github.com/project-chip/connectedhomeip) when
started with `-chip-tool /path/to/chip-tool`; without it (or in `-demo`
mode) commissioning yields a simulated device so the whole flow is
testable. Thread devices additionally need a border router on the LAN —
run the [OpenThread Border Router](https://openthread.io/guides/border-router)
alongside the bridge (an RCP dongle + `otbr-agent` on the same Pi works).
