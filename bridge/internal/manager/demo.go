package manager

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
	"github.com/mamoonk/omni-assistant/bridge/internal/protocol"
)

// DemoManager simulates a Zigbee radio: permit_join makes scripted devices
// appear (join -> interview -> ready), commands mutate state and echo
// state_changed events. Lets the full app flow run with zero hardware.
type DemoManager struct {
	connectionID string
	// joinDelay/interviewDelay tuneable for tests
	JoinDelay      time.Duration
	InterviewDelay time.Duration

	mu      sync.Mutex
	devices map[string]*device.Device
	joined  int
	events  chan protocol.Event
	ctx     context.Context
	cancel  context.CancelFunc
}

func NewDemo(connectionID string) *DemoManager {
	// ctx pre-initialized so PermitJoin is safe even before Start runs
	ctx, cancel := context.WithCancel(context.Background())
	return &DemoManager{
		connectionID:   connectionID,
		JoinDelay:      2 * time.Second,
		InterviewDelay: 2 * time.Second,
		devices:        map[string]*device.Device{},
		events:         make(chan protocol.Event, 64),
		ctx:            ctx,
		cancel:         cancel,
	}
}

func (m *DemoManager) Protocol() string { return "zigbee" }

func (m *DemoManager) Start(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	// swap in the runtime context; joins started on the placeholder keep
	// running — cancelling it here would kill them mid-interview
	m.ctx, m.cancel = context.WithCancel(ctx)
	return nil
}

func (m *DemoManager) Stop() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.cancel()
	return nil
}

func (m *DemoManager) Events() <-chan protocol.Event { return m.events }

func (m *DemoManager) Devices() []device.Device {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]device.Device, 0, len(m.devices))
	for _, d := range m.devices {
		out = append(out, *d)
	}
	return out
}

// Seed pre-loads devices (used when restoring from the store).
func (m *DemoManager) Seed(devices []device.Device) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i := range devices {
		d := devices[i]
		m.devices[d.ID] = &d
	}
	m.joined = len(devices)
}

func (m *DemoManager) PermitJoin(duration int) error {
	m.mu.Lock()
	ctx := m.ctx
	m.mu.Unlock()

	m.emit(protocol.NewEvent("zigbee", protocol.EvPermitJoin,
		map[string]any{"enabled": true, "duration": duration}))

	go func() {
		select {
		case <-time.After(m.JoinDelay):
		case <-ctx.Done():
			return
		}

		next := m.nextTemplate()
		ieee := fmt.Sprintf("0xdemo%010d", m.joined)
		m.emit(protocol.NewEvent("zigbee", protocol.EvDeviceJoined,
			map[string]any{"ieee_address": ieee, "interviewing": true}))

		select {
		case <-time.After(m.InterviewDelay):
		case <-ctx.Done():
			return
		}

		d := next(m.connectionID, ieee, m.joined)
		m.mu.Lock()
		m.devices[d.ID] = &d
		m.joined++
		m.mu.Unlock()
		m.emit(protocol.NewEvent("zigbee", protocol.EvDeviceInterviewed,
			map[string]any{"device": d}))

		m.emit(protocol.NewEvent("zigbee", protocol.EvPermitJoin,
			map[string]any{"enabled": false, "duration": 0}))
	}()
	return nil
}

func (m *DemoManager) Execute(deviceID, capability string, value any) error {
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
	applyCommand(cap, value)
	snapshot := *d
	m.mu.Unlock()

	m.emit(protocol.NewEvent("zigbee", protocol.EvStateChanged,
		map[string]any{"device": snapshot}))
	return nil
}

func applyCommand(cap *device.Capability, value any) {
	switch cap.Type {
	case device.CapPowerSwitch:
		cap.State["on"] = value == true
	case device.CapBrightness:
		cap.State["level"] = value
	case device.CapColorTemperature:
		cap.State["mireds"] = value
	case device.CapColorRgb:
		if rgb, ok := value.([]any); ok && len(rgb) == 3 {
			cap.State["r"], cap.State["g"], cap.State["b"] = rgb[0], rgb[1], rgb[2]
		}
	case device.CapTargetTemperature:
		cap.State["target"] = value
	}
}

func (m *DemoManager) emit(e protocol.Event) {
	select {
	case m.events <- e:
	default: // drop rather than block if no consumer
	}
}

type template func(connectionID, ieee string, n int) device.Device

// nextTemplate cycles bulb -> motion sensor -> smart plug.
func (m *DemoManager) nextTemplate() template {
	m.mu.Lock()
	defer m.mu.Unlock()
	templates := []template{demoBulb, demoMotion, demoPlug}
	return templates[m.joined%len(templates)]
}

func origin(connectionID, ieee string) device.Origin {
	return device.Origin{
		Type:         "nexusBridge",
		ConnectionID: connectionID,
		NativeID:     ieee,
		Protocol:     "zigbee",
	}
}

func demoBulb(connectionID, ieee string, n int) device.Device {
	return device.Device{
		ID:           "bridge:" + connectionID + ":" + ieee,
		Name:         fmt.Sprintf("Demo Bulb %d", n+1),
		Manufacturer: "Nexus Demo",
		Model:        "BULB-1",
		Origin:       origin(connectionID, ieee),
		RoomID:       "unassigned",
		Capabilities: []device.Capability{
			{Type: device.CapPowerSwitch, State: map[string]any{"on": false}},
			{Type: device.CapBrightness, State: map[string]any{"level": 100}},
			{Type: device.CapColorTemperature, State: map[string]any{"mireds": 300}},
		},
	}
}

func demoMotion(connectionID, ieee string, n int) device.Device {
	return device.Device{
		ID:           "bridge:" + connectionID + ":" + ieee,
		Name:         fmt.Sprintf("Demo Motion %d", n+1),
		Manufacturer: "Nexus Demo",
		Model:        "PIR-1",
		Origin:       origin(connectionID, ieee),
		RoomID:       "unassigned",
		Capabilities: []device.Capability{
			{Type: device.CapMotion, State: map[string]any{"active": false}},
			{Type: device.CapBattery, State: map[string]any{"value": 100, "unit": "%"}},
		},
	}
}

func demoPlug(connectionID, ieee string, n int) device.Device {
	return device.Device{
		ID:           "bridge:" + connectionID + ":" + ieee,
		Name:         fmt.Sprintf("Demo Plug %d", n+1),
		Manufacturer: "Nexus Demo",
		Model:        "PLUG-1",
		Origin:       origin(connectionID, ieee),
		RoomID:       "unassigned",
		Capabilities: []device.Capability{
			{Type: device.CapPowerSwitch, State: map[string]any{"on": false}},
		},
	}
}
