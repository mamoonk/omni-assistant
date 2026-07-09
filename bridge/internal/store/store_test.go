package store

import (
	"path/filepath"
	"testing"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
)

func TestDeviceRoundTrip(t *testing.T) {
	st, err := Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	d := device.Device{
		ID:   "bridge:b0:0x01",
		Name: "Bulb",
		Origin: device.Origin{
			Type: "nexusBridge", ConnectionID: "b0", NativeID: "0x01", Protocol: "zigbee",
		},
		RoomID: "unassigned",
		Capabilities: []device.Capability{
			{Type: device.CapPowerSwitch, State: map[string]any{"on": true}},
		},
	}
	if err := st.SaveDevice(d); err != nil {
		t.Fatal(err)
	}

	devices, err := st.Devices()
	if err != nil {
		t.Fatal(err)
	}
	if len(devices) != 1 || devices[0].ID != d.ID {
		t.Fatalf("devices = %+v", devices)
	}
	if on := devices[0].Find(device.CapPowerSwitch).State["on"]; on != true {
		t.Errorf("on = %v", on)
	}

	if err := st.DeleteDevice(d.ID); err != nil {
		t.Fatal(err)
	}
	devices, _ = st.Devices()
	if len(devices) != 0 {
		t.Errorf("expected empty store, got %d", len(devices))
	}
}
