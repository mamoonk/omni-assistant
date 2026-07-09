// Package automation is the bridge-side rule runtime (§6.2): the app syncs
// eligible rules here so they run 24/7 without the phone. JSON shapes mirror
// the Flutter app's automations_provider.
package automation

import (
	"github.com/mamoonk/omni-assistant/bridge/internal/device"
)

type Trigger struct {
	Type string `json:"type"` // "device" | "time"
	// device trigger
	DeviceID       string `json:"deviceId,omitempty"`
	CapabilityType string `json:"capabilityType,omitempty"`
	Op             string `json:"op,omitempty"` // "==", ">", "<"
	Value          any    `json:"value,omitempty"`
	// time trigger
	Hour   int `json:"hour,omitempty"`
	Minute int `json:"minute,omitempty"`
}

type Condition struct {
	Type  string `json:"type"` // "timeRange"
	Start int    `json:"start"`
	End   int    `json:"end"`
}

type Action struct {
	Type           string `json:"type"` // "setState" (scenes are flattened by the app)
	DeviceID       string `json:"deviceId"`
	CapabilityType string `json:"capabilityType"`
	Value          any    `json:"value"`
}

type Automation struct {
	ID        string     `json:"id"`
	Name      string     `json:"name"`
	Enabled   bool       `json:"enabled"`
	Trigger   Trigger    `json:"trigger"`
	Condition *Condition `json:"condition,omitempty"`
	Actions   []Action   `json:"actions"`
}

// StateKeyFor mirrors the app's default observed key per capability.
func StateKeyFor(capabilityType string) string {
	switch capabilityType {
	case device.CapPowerSwitch:
		return "on"
	case device.CapMotion, device.CapContact:
		return "active"
	case device.CapBrightness:
		return "level"
	case device.CapTargetTemperature:
		return "target"
	default:
		return "value"
	}
}

// Matches evaluates a device trigger against a device's current state.
func (t Trigger) Matches(d *device.Device) bool {
	if t.Type != "device" || d == nil {
		return false
	}
	cap := d.Find(t.CapabilityType)
	if cap == nil {
		return false
	}
	state, ok := cap.State[StateKeyFor(t.CapabilityType)]
	if !ok || state == nil {
		return false
	}
	op := t.Op
	if op == "" {
		op = "=="
	}
	return Compare(state, op, t.Value)
}

func (c *Condition) Holds(nowMinutes int) bool {
	if c == nil {
		return true
	}
	if c.Start <= c.End {
		return nowMinutes >= c.Start && nowMinutes <= c.End
	}
	// overnight window, e.g. 22:00-06:00
	return nowMinutes >= c.Start || nowMinutes <= c.End
}

// Compare handles the JSON type zoo: numbers arrive as float64, sometimes int.
func Compare(state any, op string, target any) bool {
	sn, sIsNum := toFloat(state)
	tn, tIsNum := toFloat(target)
	switch op {
	case "==":
		if sIsNum && tIsNum {
			return sn == tn
		}
		return state == target
	case ">":
		return sIsNum && tIsNum && sn > tn
	case "<":
		return sIsNum && tIsNum && sn < tn
	default:
		return false
	}
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case float32:
		return float64(n), true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	}
	return 0, false
}
