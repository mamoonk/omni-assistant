// Package manager defines the radio orchestrator contract (§5.2).
// Real implementations wrap Zigbee2MQTT / Z-Wave JS UI subprocesses; the
// demo implementation simulates joins so the app wizard works without radios.
package manager

import (
	"context"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
	"github.com/mamoonk/omni-assistant/bridge/internal/protocol"
)

type RadioManager interface {
	// Protocol domain this manager serves: "zigbee", "zwave".
	Protocol() string
	Start(ctx context.Context) error
	Stop() error

	// PermitJoin opens the network for new devices for duration seconds.
	PermitJoin(duration int) error
	Devices() []device.Device
	// Execute applies a capability command to one device.
	Execute(deviceID, capability string, value any) error

	// Events emits joins, interviews, and state changes.
	Events() <-chan protocol.Event
}
