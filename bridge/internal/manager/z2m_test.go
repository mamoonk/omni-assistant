package manager

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	mqtt "github.com/mochi-mqtt/server/v2"
	"github.com/mochi-mqtt/server/v2/packets"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
	"github.com/mamoonk/omni-assistant/bridge/internal/protocol"
)

func bulbEntry() map[string]any {
	raw := `{
		"type": "Router",
		"friendly_name": "office_bulb",
		"ieee_address": "0x00158d0001e5c123",
		"definition": {
			"vendor": "IKEA",
			"model": "LED1924G9",
			"exposes": [{
				"type": "light",
				"features": [
					{"type": "binary", "name": "state", "property": "state"},
					{"type": "numeric", "name": "brightness", "property": "brightness"},
					{"type": "numeric", "name": "color_temp", "property": "color_temp"}
				]
			}]
		}
	}`
	var entry map[string]any
	_ = json.Unmarshal([]byte(raw), &entry)
	return entry
}

func TestMapZ2MDevice(t *testing.T) {
	d := MapZ2MDevice(bulbEntry(), "b0")
	if d == nil {
		t.Fatal("bulb not mapped")
	}
	if d.ID != "bridge:b0:office_bulb" {
		t.Errorf("id = %s", d.ID)
	}
	for _, want := range []string{
		device.CapPowerSwitch, device.CapBrightness, device.CapColorTemperature,
	} {
		if d.Find(want) == nil {
			t.Errorf("missing capability %s", want)
		}
	}
	if MapZ2MDevice(map[string]any{"type": "Coordinator"}, "b0") != nil {
		t.Error("coordinator should be skipped")
	}
}

func TestApplyZ2MState(t *testing.T) {
	d := MapZ2MDevice(bulbEntry(), "b0")
	changed := ApplyZ2MState(d, map[string]any{
		"state": "ON", "brightness": float64(127), "linkquality": float64(66),
	})
	if !changed {
		t.Fatal("state change not detected")
	}
	if on := d.Find(device.CapPowerSwitch).State["on"]; on != true {
		t.Errorf("on = %v", on)
	}
	if level := d.Find(device.CapBrightness).State["level"]; level != 50 {
		t.Errorf("level = %v, want 50", level)
	}
}

func TestZ2MCommandPayload(t *testing.T) {
	p, err := Z2MCommandPayload(device.CapPowerSwitch, true)
	if err != nil || p["state"] != "ON" {
		t.Errorf("power payload = %v (%v)", p, err)
	}
	p, err = Z2MCommandPayload(device.CapBrightness, float64(50))
	if err != nil || p["brightness"] != 127 {
		t.Errorf("brightness payload = %v (%v)", p, err)
	}
	if _, err = Z2MCommandPayload("bogus", 1); err == nil {
		t.Error("expected error for unknown capability")
	}
}

// End-to-end through the embedded broker: device list -> state -> events.
func TestZ2MManagerViaEmbeddedBroker(t *testing.T) {
	z := NewZ2M(Z2MOptions{
		ConnectionID: "b0",
		BrokerAddr:   "127.0.0.1:0", // ephemeral port
	})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	if err := z.Start(ctx); err != nil {
		t.Fatal(err)
	}

	list, _ := json.Marshal([]any{bulbEntry()})
	if err := z.Broker().Publish("zigbee2mqtt/bridge/devices", list, false, 0); err != nil {
		t.Fatal(err)
	}

	waitFor(t, func() bool { return len(z.Devices()) == 1 }, "device list processed")

	// live state update -> state_changed event
	state := []byte(`{"state":"ON","brightness":254}`)
	if err := z.Broker().Publish("zigbee2mqtt/office_bulb", state, false, 0); err != nil {
		t.Fatal(err)
	}
	e := nextEvent(t, z.Events())
	if e.Event != protocol.EvStateChanged {
		t.Fatalf("event = %s, want state_changed", e.Event)
	}
	d := e.Data.(map[string]any)["device"].(device.Device)
	if d.Find(device.CapBrightness).State["level"] != 100 {
		t.Errorf("brightness = %v", d.Find(device.CapBrightness).State["level"])
	}

	// join + interview bridge events translate to protocol events
	join := []byte(`{"type":"device_joined","data":{"ieee_address":"0xabc"}}`)
	_ = z.Broker().Publish("zigbee2mqtt/bridge/event", join, false, 0)
	if e := nextEvent(t, z.Events()); e.Event != protocol.EvDeviceJoined {
		t.Fatalf("event = %s, want device_joined", e.Event)
	}

	interview, _ := json.Marshal(map[string]any{
		"type": "device_interview",
		"data": map[string]any{
			"status":        "successful",
			"friendly_name": "new_sensor",
			"ieee_address":  "0xabc",
			"definition": map[string]any{
				"vendor": "Aqara",
				"model":  "MCCGQ11LM",
				"exposes": []any{
					map[string]any{"type": "binary", "property": "contact"},
				},
			},
		},
	})
	_ = z.Broker().Publish("zigbee2mqtt/bridge/event", interview, false, 0)
	if e := nextEvent(t, z.Events()); e.Event != protocol.EvDeviceInterviewed {
		t.Fatalf("event = %s, want device_interviewed", e.Event)
	}
	waitFor(t, func() bool { return len(z.Devices()) == 2 }, "interviewed device cached")

	// Execute publishes to <base>/<name>/set
	got := make(chan []byte, 1)
	err := z.Broker().Subscribe("zigbee2mqtt/office_bulb/set", 2,
		func(_ *mqtt.Client, _ packets.Subscription, pk packets.Packet) {
			got <- pk.Payload
		})
	if err != nil {
		t.Fatal(err)
	}
	if err := z.Execute("bridge:b0:office_bulb", device.CapPowerSwitch, true); err != nil {
		t.Fatal(err)
	}
	select {
	case payload := <-got:
		var cmd map[string]any
		_ = json.Unmarshal(payload, &cmd)
		if cmd["state"] != "ON" {
			t.Errorf("set payload = %s", payload)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("no /set publish observed")
	}
}

func waitFor(t *testing.T, cond func() bool, what string) {
	t.Helper()
	deadline := time.After(3 * time.Second)
	for !cond() {
		select {
		case <-deadline:
			t.Fatalf("timeout waiting for %s", what)
		case <-time.After(10 * time.Millisecond):
		}
	}
}

func nextEvent(t *testing.T, ch <-chan protocol.Event) protocol.Event {
	t.Helper()
	select {
	case e := <-ch:
		return e
	case <-time.After(3 * time.Second):
		t.Fatal("timeout waiting for event")
		return protocol.Event{}
	}
}
