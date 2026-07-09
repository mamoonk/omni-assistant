package manager

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"

	mqtt "github.com/mochi-mqtt/server/v2"
	"github.com/mochi-mqtt/server/v2/hooks/auth"
	"github.com/mochi-mqtt/server/v2/listeners"
	"github.com/mochi-mqtt/server/v2/packets"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
	"github.com/mamoonk/omni-assistant/bridge/internal/protocol"
)

// Z2MOptions configures the Zigbee manager.
type Z2MOptions struct {
	ConnectionID string
	// BrokerAddr is the embedded MQTT broker listen address (":1884").
	// Zigbee2MQTT must be pointed at it (mqtt.server in its config).
	BrokerAddr string
	BaseTopic  string // default "zigbee2mqtt"
	// Z2MCommand, when set, is supervised as a child process
	// (e.g. ["node", "/opt/zigbee2mqtt/index.js"]). Empty = externally run.
	Z2MCommand []string
}

// Z2M manages a Zigbee2MQTT instance (§5.2): embeds an MQTT broker so no
// external broker is needed, optionally supervises the z2m process, and
// translates z2m topics to the Nexus protocol.
type Z2M struct {
	opts   Z2MOptions
	broker *mqtt.Server

	mu      sync.Mutex
	devices map[string]*device.Device // friendly_name -> device
	events  chan protocol.Event
}

func NewZ2M(opts Z2MOptions) *Z2M {
	if opts.BaseTopic == "" {
		opts.BaseTopic = "zigbee2mqtt"
	}
	if opts.BrokerAddr == "" {
		opts.BrokerAddr = ":1884"
	}
	if opts.ConnectionID == "" {
		opts.ConnectionID = "bridge0"
	}
	return &Z2M{
		opts:    opts,
		devices: map[string]*device.Device{},
		events:  make(chan protocol.Event, 64),
	}
}

func (z *Z2M) Protocol() string              { return "zigbee" }
func (z *Z2M) Events() <-chan protocol.Event { return z.events }

// Broker exposes the embedded server (tests publish z2m traffic through it).
func (z *Z2M) Broker() *mqtt.Server { return z.broker }

func (z *Z2M) Start(ctx context.Context) error {
	server := mqtt.New(&mqtt.Options{InlineClient: true})
	if err := server.AddHook(new(auth.AllowHook), nil); err != nil {
		return err
	}
	tcp := listeners.NewTCP(listeners.Config{ID: "z2m", Address: z.opts.BrokerAddr})
	if err := server.AddListener(tcp); err != nil {
		return err
	}
	go func() {
		if err := server.Serve(); err != nil {
			log.Printf("z2m broker: %v", err)
		}
	}()
	z.broker = server

	base := z.opts.BaseTopic
	if err := server.Subscribe(base+"/#", 1, z.onMessage); err != nil {
		return err
	}

	if len(z.opts.Z2MCommand) > 0 {
		sup := &Supervisor{Name: "zigbee2mqtt", Command: z.opts.Z2MCommand}
		go sup.Run(ctx)
	}

	go func() {
		<-ctx.Done()
		_ = server.Close()
	}()
	return nil
}

func (z *Z2M) Stop() error {
	if z.broker != nil {
		return z.broker.Close()
	}
	return nil
}

func (z *Z2M) onMessage(_ *mqtt.Client, _ packets.Subscription, pk packets.Packet) {
	topic := pk.TopicName
	base := z.opts.BaseTopic

	switch {
	case topic == base+"/bridge/devices":
		z.onDeviceList(pk.Payload)
	case topic == base+"/bridge/event":
		z.onBridgeEvent(pk.Payload)
	case strings.HasPrefix(topic, base+"/"):
		name := strings.TrimPrefix(topic, base+"/")
		// ignore bridge/*, availability, and command echoes
		if strings.HasPrefix(name, "bridge") || strings.Contains(name, "/") {
			return
		}
		z.onDeviceState(name, pk.Payload)
	}
}

func (z *Z2M) onDeviceList(payload []byte) {
	var entries []map[string]any
	if err := json.Unmarshal(payload, &entries); err != nil {
		return
	}
	z.mu.Lock()
	for _, entry := range entries {
		if d := MapZ2MDevice(entry, z.opts.ConnectionID); d != nil {
			// keep live state if we already track this device
			if existing, ok := z.devices[d.Origin.NativeID]; ok {
				d.RoomID = existing.RoomID
				for i, c := range d.Capabilities {
					if prev := existing.Find(c.Type); prev != nil {
						d.Capabilities[i].State = prev.State
					}
				}
			}
			z.devices[d.Origin.NativeID] = d
		}
	}
	z.mu.Unlock()
}

func (z *Z2M) onBridgeEvent(payload []byte) {
	var event struct {
		Type string         `json:"type"`
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(payload, &event); err != nil {
		return
	}
	switch event.Type {
	case "device_joined":
		z.emit(protocol.NewEvent("zigbee", protocol.EvDeviceJoined, map[string]any{
			"ieee_address": event.Data["ieee_address"],
			"interviewing": true,
		}))
	case "device_interview":
		if event.Data["status"] != "successful" {
			return
		}
		// interview payload carries the definition; map it directly
		entry := map[string]any{
			"type":          "EndDevice",
			"friendly_name": event.Data["friendly_name"],
			"definition":    event.Data["definition"],
		}
		d := MapZ2MDevice(entry, z.opts.ConnectionID)
		if d == nil {
			return
		}
		z.mu.Lock()
		z.devices[d.Origin.NativeID] = d
		z.mu.Unlock()
		z.emit(protocol.NewEvent("zigbee", protocol.EvDeviceInterviewed,
			map[string]any{"device": *d}))
	case "permit_join_changed":
		z.emit(protocol.NewEvent("zigbee", protocol.EvPermitJoin, event.Data))
	}
}

func (z *Z2M) onDeviceState(name string, payload []byte) {
	var state map[string]any
	if err := json.Unmarshal(payload, &state); err != nil {
		return
	}
	z.mu.Lock()
	d, ok := z.devices[name]
	if !ok {
		z.mu.Unlock()
		return
	}
	changed := ApplyZ2MState(d, state)
	snapshot := *d
	z.mu.Unlock()

	if changed {
		z.emit(protocol.NewEvent("zigbee", protocol.EvStateChanged,
			map[string]any{"device": snapshot}))
	}
}

func (z *Z2M) Devices() []device.Device {
	z.mu.Lock()
	defer z.mu.Unlock()
	out := make([]device.Device, 0, len(z.devices))
	for _, d := range z.devices {
		out = append(out, *d)
	}
	return out
}

func (z *Z2M) PermitJoin(duration int) error {
	body, _ := json.Marshal(map[string]any{"value": true, "time": duration})
	return z.publish(z.opts.BaseTopic+"/bridge/request/permit_join", body)
}

func (z *Z2M) Execute(deviceID, capability string, value any) error {
	z.mu.Lock()
	var target *device.Device
	for _, d := range z.devices {
		if d.ID == deviceID {
			target = d
			break
		}
	}
	z.mu.Unlock()
	if target == nil {
		return fmt.Errorf("unknown device %s", deviceID)
	}

	payload, err := Z2MCommandPayload(capability, value)
	if err != nil {
		return err
	}
	body, _ := json.Marshal(payload)
	return z.publish(
		z.opts.BaseTopic+"/"+target.Origin.NativeID+"/set", body)
}

func (z *Z2M) publish(topic string, body []byte) error {
	if z.broker == nil {
		return fmt.Errorf("broker not started")
	}
	return z.broker.Publish(topic, body, false, 0)
}

func (z *Z2M) emit(e protocol.Event) {
	select {
	case z.events <- e:
	default:
	}
}
