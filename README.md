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
- [ ] Phase 4 — manual IP devices, automation composer + bridge runtime
- [ ] Phase 5 — Matter, Thread border router, polish, store launch
