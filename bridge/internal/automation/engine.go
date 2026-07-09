package automation

import (
	"log"
	"sync"
	"time"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
)

// Executor applies one capability command; the server routes it to managers.
type Executor func(deviceID, capability string, value any) error

// Engine evaluates automations against device state transitions and the
// clock. Device triggers are edge-fired: they run only when the trigger goes
// from not-matching to matching.
type Engine struct {
	mu          sync.Mutex
	automations map[string]Automation
	lastMatch   map[string]bool // automation id -> trigger matched last time
	lastMinute  string
	exec        Executor
	// OnFired, when set, observes fired automations (protocol event fan-out).
	OnFired func(Automation)
}

func NewEngine(exec Executor) *Engine {
	return &Engine{
		automations: map[string]Automation{},
		lastMatch:   map[string]bool{},
		exec:        exec,
	}
}

// SetAutomations replaces the rule set. currentDevices seeds edge state so
// an already-matching trigger doesn't fire immediately after sync.
func (e *Engine) SetAutomations(automations []Automation, currentDevices []device.Device) {
	byID := map[string]*device.Device{}
	for i := range currentDevices {
		byID[currentDevices[i].ID] = &currentDevices[i]
	}

	e.mu.Lock()
	defer e.mu.Unlock()
	e.automations = map[string]Automation{}
	e.lastMatch = map[string]bool{}
	for _, a := range automations {
		e.automations[a.ID] = a
		if a.Trigger.Type == "device" {
			e.lastMatch[a.ID] = a.Trigger.Matches(byID[a.Trigger.DeviceID])
		}
	}
}

func (e *Engine) Automations() []Automation {
	e.mu.Lock()
	defer e.mu.Unlock()
	out := make([]Automation, 0, len(e.automations))
	for _, a := range e.automations {
		out = append(out, a)
	}
	return out
}

// OnStateChanged re-evaluates device triggers for the changed device.
func (e *Engine) OnStateChanged(d device.Device) {
	now := time.Now()
	var fire []Automation

	e.mu.Lock()
	for id, a := range e.automations {
		if a.Trigger.Type != "device" || a.Trigger.DeviceID != d.ID {
			continue
		}
		matches := a.Trigger.Matches(&d)
		was := e.lastMatch[id]
		e.lastMatch[id] = matches
		if !was && matches && a.Enabled &&
			a.Condition.Holds(now.Hour()*60+now.Minute()) {
			fire = append(fire, a)
		}
	}
	e.mu.Unlock()

	for _, a := range fire {
		e.run(a)
	}
}

// Tick fires time triggers; call every <60s. Guarded to once per minute.
func (e *Engine) Tick(now time.Time) {
	minuteKey := now.Format("2006-01-02T15:04")

	var fire []Automation
	e.mu.Lock()
	if minuteKey == e.lastMinute {
		e.mu.Unlock()
		return
	}
	e.lastMinute = minuteKey
	for _, a := range e.automations {
		if a.Enabled && a.Trigger.Type == "time" &&
			a.Trigger.Hour == now.Hour() && a.Trigger.Minute == now.Minute() &&
			a.Condition.Holds(now.Hour()*60+now.Minute()) {
			fire = append(fire, a)
		}
	}
	e.mu.Unlock()

	for _, a := range fire {
		e.run(a)
	}
}

func (e *Engine) run(a Automation) {
	log.Printf("automation %q fired", a.Name)
	for _, action := range a.Actions {
		if action.Type != "setState" {
			continue
		}
		if err := e.exec(action.DeviceID, action.CapabilityType, action.Value); err != nil {
			// one failing action must not stop the rest
			log.Printf("automation %q: action on %s failed: %v", a.Name, action.DeviceID, err)
		}
	}
	if e.OnFired != nil {
		e.OnFired(a)
	}
}
