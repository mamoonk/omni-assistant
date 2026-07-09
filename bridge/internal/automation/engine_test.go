package automation

import (
	"sync"
	"testing"
	"time"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
)

type call struct {
	deviceID, capability string
	value                any
}

type recorder struct {
	mu    sync.Mutex
	calls []call
}

func (r *recorder) exec(deviceID, capability string, value any) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = append(r.calls, call{deviceID, capability, value})
	return nil
}

func (r *recorder) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.calls)
}

func motionDevice(active bool) device.Device {
	return device.Device{
		ID: "bridge:b0:motion1",
		Capabilities: []device.Capability{
			{Type: device.CapMotion, State: map[string]any{"active": active}},
		},
	}
}

func motionAutomation(enabled bool) Automation {
	return Automation{
		ID:      "a1",
		Name:    "motion -> plug",
		Enabled: enabled,
		Trigger: Trigger{
			Type:           "device",
			DeviceID:       "bridge:b0:motion1",
			CapabilityType: device.CapMotion,
			Value:          true,
		},
		Actions: []Action{{
			Type:           "setState",
			DeviceID:       "bridge:b0:plug1",
			CapabilityType: device.CapPowerSwitch,
			Value:          true,
		}},
	}
}

func TestDeviceTriggerEdgeFiring(t *testing.T) {
	rec := &recorder{}
	e := NewEngine(rec.exec)
	e.SetAutomations([]Automation{motionAutomation(true)},
		[]device.Device{motionDevice(false)})

	// inactive -> active: fires
	e.OnStateChanged(motionDevice(true))
	if rec.count() != 1 {
		t.Fatalf("calls = %d, want 1", rec.count())
	}
	// still active: no re-fire
	e.OnStateChanged(motionDevice(true))
	if rec.count() != 1 {
		t.Fatalf("calls = %d after repeat, want 1", rec.count())
	}
	// falls back, rises again: fires again
	e.OnStateChanged(motionDevice(false))
	e.OnStateChanged(motionDevice(true))
	if rec.count() != 2 {
		t.Fatalf("calls = %d after second edge, want 2", rec.count())
	}
}

func TestAlreadyMatchingTriggerDoesNotFireOnSync(t *testing.T) {
	rec := &recorder{}
	e := NewEngine(rec.exec)
	// motion already active when the rule set arrives
	e.SetAutomations([]Automation{motionAutomation(true)},
		[]device.Device{motionDevice(true)})

	e.OnStateChanged(motionDevice(true))
	if rec.count() != 0 {
		t.Fatalf("calls = %d, want 0 (no edge)", rec.count())
	}
}

func TestDisabledAutomationDoesNotFire(t *testing.T) {
	rec := &recorder{}
	e := NewEngine(rec.exec)
	e.SetAutomations([]Automation{motionAutomation(false)},
		[]device.Device{motionDevice(false)})
	e.OnStateChanged(motionDevice(true))
	if rec.count() != 0 {
		t.Fatalf("calls = %d, want 0", rec.count())
	}
}

func TestTimeTriggerMinuteGuard(t *testing.T) {
	rec := &recorder{}
	e := NewEngine(rec.exec)
	e.SetAutomations([]Automation{{
		ID:      "t1",
		Name:    "morning",
		Enabled: true,
		Trigger: Trigger{Type: "time", Hour: 7, Minute: 30},
		Actions: []Action{{
			Type: "setState", DeviceID: "d", CapabilityType: device.CapPowerSwitch, Value: true,
		}},
	}}, nil)

	e.Tick(time.Date(2026, 1, 1, 7, 30, 5, 0, time.UTC))
	e.Tick(time.Date(2026, 1, 1, 7, 30, 25, 0, time.UTC)) // same minute
	if rec.count() != 1 {
		t.Fatalf("calls = %d, want 1", rec.count())
	}
	e.Tick(time.Date(2026, 1, 2, 7, 30, 5, 0, time.UTC)) // next day
	if rec.count() != 2 {
		t.Fatalf("calls = %d, want 2", rec.count())
	}
}

func TestConditionWindow(t *testing.T) {
	overnight := &Condition{Type: "timeRange", Start: 22 * 60, End: 6 * 60}
	if !overnight.Holds(23 * 60) {
		t.Error("23:00 should be inside 22:00-06:00")
	}
	if !overnight.Holds(3 * 60) {
		t.Error("03:00 should be inside 22:00-06:00")
	}
	if overnight.Holds(12 * 60) {
		t.Error("12:00 should be outside 22:00-06:00")
	}
	var none *Condition
	if !none.Holds(0) {
		t.Error("nil condition must always hold")
	}
}

func TestCompareNumericJSONTypes(t *testing.T) {
	// JSON decodes numbers as float64; app may send ints
	if !Compare(float64(18), "<", 19) {
		t.Error("18 < 19 expected true")
	}
	if !Compare(50, "==", float64(50)) {
		t.Error("50 == 50.0 expected true")
	}
	if Compare("on", ">", 1) {
		t.Error("non-numeric > must be false")
	}
}
