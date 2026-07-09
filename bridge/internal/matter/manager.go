package matter

import (
	"context"
	"fmt"
	"os/exec"
	"sync"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
	"github.com/mamoonk/omni-assistant/bridge/internal/protocol"
)

// Manager is the Matter controller front. With Simulate on (demo mode, or
// no chip-tool installed) commissioning a valid payload yields a simulated
// on/off device — the full app flow works without hardware. With
// ChipToolPath set it shells out to chip-tool for real commissioning
// (§7 Matter SDK integration point).
type Manager struct {
	ConnectionID string
	Simulate     bool
	// ChipToolPath, when set and Simulate is false, is invoked as
	// `chip-tool pairing code <node-id> <payload>`.
	ChipToolPath string

	mu      sync.Mutex
	devices map[string]*device.Device
	nextID  int
	events  chan protocol.Event
	ctx     context.Context
}

func New(connectionID string, simulate bool, chipToolPath string) *Manager {
	return &Manager{
		ConnectionID: connectionID,
		Simulate:     simulate,
		ChipToolPath: chipToolPath,
		devices:      map[string]*device.Device{},
		events:       make(chan protocol.Event, 64),
	}
}

func (m *Manager) Protocol() string              { return "matter" }
func (m *Manager) Events() <-chan protocol.Event { return m.events }

func (m *Manager) Start(ctx context.Context) error {
	m.ctx = ctx
	return nil
}

func (m *Manager) Stop() error { return nil }

// PermitJoin is not how Matter works; commissioning uses pairing codes.
func (m *Manager) PermitJoin(int) error {
	return fmt.Errorf("matter devices are added by pairing code, use commission")
}

// Seed restores devices from the store.
func (m *Manager) Seed(devices []device.Device) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i := range devices {
		if devices[i].Origin.Protocol != "matter" {
			continue
		}
		d := devices[i]
		m.devices[d.ID] = &d
		m.nextID++
	}
}

// Commission parses the payload and commissions the device. Emits the same
// join/interview events as the Zigbee flow so the app wizard is reused.
func (m *Manager) Commission(code string) error {
	payload, err := ParseQR(code)
	if err != nil {
		return err
	}

	m.emit(protocol.NewEvent("matter", protocol.EvDeviceJoined, map[string]any{
		"ieee_address": fmt.Sprintf("matter-%d", payload.Discriminator),
		"interviewing": true,
	}))

	if !m.Simulate {
		if m.ChipToolPath == "" {
			return fmt.Errorf("no Matter controller backend: install chip-tool and pass -chip-tool")
		}
		return m.commissionWithChipTool(code, payload)
	}

	m.mu.Lock()
	m.nextID++
	n := m.nextID
	native := fmt.Sprintf("matter-%d-%d", payload.Discriminator, n)
	d := &device.Device{
		ID:           "bridge:" + m.ConnectionID + ":" + native,
		Name:         fmt.Sprintf("Matter Device %d", n),
		Manufacturer: fmt.Sprintf("VID 0x%04X", payload.VendorID),
		Model:        fmt.Sprintf("PID 0x%04X", payload.ProductID),
		Origin: device.Origin{
			Type:         "nexusBridge",
			ConnectionID: m.ConnectionID,
			NativeID:     native,
			Protocol:     "matter",
		},
		RoomID: "unassigned",
		Capabilities: []device.Capability{
			{Type: device.CapPowerSwitch, State: map[string]any{"on": false}},
		},
	}
	m.devices[d.ID] = d
	snapshot := *d
	m.mu.Unlock()

	m.emit(protocol.NewEvent("matter", protocol.EvDeviceInterviewed,
		map[string]any{"device": snapshot}))
	return nil
}

func (m *Manager) commissionWithChipTool(code string, payload *OnboardingPayload) error {
	m.mu.Lock()
	m.nextID++
	nodeID := m.nextID
	m.mu.Unlock()
	cmd := exec.CommandContext(m.ctx, m.ChipToolPath,
		"pairing", "code", fmt.Sprint(nodeID), code)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("chip-tool commissioning failed: %v: %s", err, out)
	}
	// post-commissioning attribute subscription is the next hardware step;
	// register a bare on/off device for control via chip-tool onoff
	m.mu.Lock()
	native := fmt.Sprintf("matter-node-%d", nodeID)
	d := &device.Device{
		ID:   "bridge:" + m.ConnectionID + ":" + native,
		Name: fmt.Sprintf("Matter Node %d", nodeID),
		Origin: device.Origin{
			Type: "nexusBridge", ConnectionID: m.ConnectionID,
			NativeID: native, Protocol: "matter",
		},
		RoomID: "unassigned",
		Capabilities: []device.Capability{
			{Type: device.CapPowerSwitch, State: map[string]any{"on": false}},
		},
	}
	m.devices[d.ID] = d
	snapshot := *d
	m.mu.Unlock()
	m.emit(protocol.NewEvent("matter", protocol.EvDeviceInterviewed,
		map[string]any{"device": snapshot}))
	_ = payload
	return nil
}

func (m *Manager) Devices() []device.Device {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]device.Device, 0, len(m.devices))
	for _, d := range m.devices {
		out = append(out, *d)
	}
	return out
}

func (m *Manager) Execute(deviceID, capability string, value any) error {
	m.mu.Lock()
	d, ok := m.devices[deviceID]
	if !ok {
		m.mu.Unlock()
		return fmt.Errorf("unknown device %s", deviceID)
	}
	cap := d.Find(capability)
	if cap == nil {
		m.mu.Unlock()
		return fmt.Errorf("device %s has no capability %s", deviceID, capability)
	}
	if capability == device.CapPowerSwitch {
		cap.State["on"] = value == true
	}
	snapshot := *d
	m.mu.Unlock()

	if !m.Simulate && m.ChipToolPath != "" {
		// real control path: chip-tool onoff on/off <node> 1
		op := "off"
		if value == true {
			op = "on"
		}
		nodeID := "1" // TODO(hardware): track node ids per device
		cmd := exec.CommandContext(m.ctx, m.ChipToolPath, "onoff", op, nodeID, "1")
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("chip-tool onoff failed: %v: %s", err, out)
		}
	}

	m.emit(protocol.NewEvent("matter", protocol.EvStateChanged,
		map[string]any{"device": snapshot}))
	return nil
}

func (m *Manager) emit(e protocol.Event) {
	select {
	case m.events <- e:
	default:
	}
}
