// Package protocol defines the Nexus WebSocket protocol envelopes (§5.3).
package protocol

import "encoding/json"

// Command is sent App -> Bridge.
type Command struct {
	ID     string          `json:"id"`
	Type   string          `json:"type"` // always "command"
	Domain string          `json:"domain"`
	Action string          `json:"action"`
	Params json.RawMessage `json:"params,omitempty"`
}

// Result answers one Command, Bridge -> App.
type Result struct {
	ID      string `json:"id"`
	Type    string `json:"type"` // always "result"
	Success bool   `json:"success"`
	Result  any    `json:"result,omitempty"`
	Error   string `json:"error,omitempty"`
}

// Event is pushed Bridge -> App, unsolicited.
type Event struct {
	Type   string `json:"type"` // always "event"
	Domain string `json:"domain"`
	Event  string `json:"event"`
	Data   any    `json:"data,omitempty"`
}

func OK(id string, result any) Result {
	return Result{ID: id, Type: "result", Success: true, Result: result}
}

func Fail(id string, err error) Result {
	return Result{ID: id, Type: "result", Success: false, Error: err.Error()}
}

func NewEvent(domain, event string, data any) Event {
	return Event{Type: "event", Domain: domain, Event: event, Data: data}
}

// Well-known event names.
const (
	EvDeviceJoined      = "device_joined"
	EvDeviceInterviewed = "device_interviewed"
	EvStateChanged      = "state_changed"
	EvPermitJoin        = "permit_join_changed"
)
