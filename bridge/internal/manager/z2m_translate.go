package manager

import (
	"fmt"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
)

// Zigbee2MQTT publishes brightness as 0..254.
const z2mBrightnessMax = 254

// MapZ2MDevice converts one entry of `<base>/bridge/devices` into a Device.
// Returns nil for the coordinator and devices without a definition.
func MapZ2MDevice(entry map[string]any, connectionID string) *device.Device {
	if entry["type"] == "Coordinator" {
		return nil
	}
	definition, _ := entry["definition"].(map[string]any)
	friendlyName, _ := entry["friendly_name"].(string)
	if definition == nil || friendlyName == "" {
		return nil
	}

	var caps []device.Capability
	if exposes, ok := definition["exposes"].([]any); ok {
		for _, e := range exposes {
			if expose, ok := e.(map[string]any); ok {
				caps = append(caps, parseExpose(expose)...)
			}
		}
	}
	if len(caps) == 0 {
		return nil
	}

	vendor, _ := definition["vendor"].(string)
	model, _ := definition["model"].(string)
	return &device.Device{
		ID:           "bridge:" + connectionID + ":" + friendlyName,
		Name:         friendlyName,
		Manufacturer: vendor,
		Model:        model,
		Origin: device.Origin{
			Type:         "nexusBridge",
			ConnectionID: connectionID,
			NativeID:     friendlyName,
			Protocol:     "zigbee",
		},
		RoomID:       "unassigned",
		Capabilities: caps,
	}
}

func parseExpose(expose map[string]any) []device.Capability {
	switch expose["type"] {
	case "light", "switch":
		var caps []device.Capability
		features, _ := expose["features"].([]any)
		for _, f := range features {
			feature, ok := f.(map[string]any)
			if !ok {
				continue
			}
			switch feature["property"] {
			case "state":
				caps = append(caps, device.Capability{
					Type: device.CapPowerSwitch, State: map[string]any{"on": false}})
			case "brightness":
				caps = append(caps, device.Capability{
					Type: device.CapBrightness, State: map[string]any{"level": 0}})
			case "color_temp":
				caps = append(caps, device.Capability{
					Type: device.CapColorTemperature, State: map[string]any{"mireds": 300}})
			case "color":
				caps = append(caps, device.Capability{
					Type:  device.CapColorRgb,
					State: map[string]any{"r": 255, "g": 255, "b": 255}})
			}
		}
		return caps

	case "climate":
		var caps []device.Capability
		features, _ := expose["features"].([]any)
		for _, f := range features {
			feature, ok := f.(map[string]any)
			if !ok {
				continue
			}
			switch feature["property"] {
			case "occupied_heating_setpoint", "current_heating_setpoint":
				caps = append(caps, device.Capability{
					Type: device.CapTargetTemperature,
					State: map[string]any{
						"target": 21,
						"min":    numOr(feature["value_min"], 7),
						"max":    numOr(feature["value_max"], 35),
					}})
			case "local_temperature":
				caps = append(caps, device.Capability{
					Type:  device.CapCurrentTemperature,
					State: map[string]any{"value": nil, "unit": "°C"}})
			}
		}
		return caps

	case "binary":
		switch expose["property"] {
		case "occupancy", "presence":
			return []device.Capability{{
				Type: device.CapMotion, State: map[string]any{"active": false}}}
		// z2m: contact == true means CLOSED; active means open in our model
		case "contact":
			return []device.Capability{{
				Type: device.CapContact, State: map[string]any{"active": false}}}
		}
		return nil

	case "numeric":
		capType := ""
		switch expose["property"] {
		case "temperature":
			capType = device.CapCurrentTemperature
		case "humidity":
			capType = device.CapHumidity
		case "battery":
			capType = device.CapBattery
		}
		if capType == "" {
			return nil
		}
		unit, _ := expose["unit"].(string)
		return []device.Capability{{
			Type: capType, State: map[string]any{"value": nil, "unit": unit}}}
	}
	return nil
}

// ApplyZ2MState folds a state-topic payload into the device's capabilities.
// Returns true if anything changed.
func ApplyZ2MState(d *device.Device, payload map[string]any) bool {
	changed := false
	for key, value := range payload {
		switch key {
		case "state":
			if c := d.Find(device.CapPowerSwitch); c != nil {
				c.State["on"] = value == "ON"
				changed = true
			}
		case "brightness":
			if c := d.Find(device.CapBrightness); c != nil {
				if v, ok := value.(float64); ok {
					c.State["level"] = int(v/z2mBrightnessMax*100 + 0.5)
					changed = true
				}
			}
		case "color_temp":
			if c := d.Find(device.CapColorTemperature); c != nil {
				c.State["mireds"] = value
				changed = true
			}
		case "occupancy", "presence":
			if c := d.Find(device.CapMotion); c != nil {
				c.State["active"] = value == true
				changed = true
			}
		case "contact":
			if c := d.Find(device.CapContact); c != nil {
				c.State["active"] = value == false // contact=false -> open
				changed = true
			}
		case "temperature", "local_temperature":
			if c := d.Find(device.CapCurrentTemperature); c != nil {
				c.State["value"] = value
				changed = true
			}
		case "humidity":
			if c := d.Find(device.CapHumidity); c != nil {
				c.State["value"] = value
				changed = true
			}
		case "battery":
			if c := d.Find(device.CapBattery); c != nil {
				c.State["value"] = value
				changed = true
			}
		case "occupied_heating_setpoint", "current_heating_setpoint":
			if c := d.Find(device.CapTargetTemperature); c != nil {
				c.State["target"] = value
				changed = true
			}
		}
	}
	return changed
}

// Z2MCommandPayload builds the JSON body for `<base>/<name>/set`.
func Z2MCommandPayload(capType string, value any) (map[string]any, error) {
	switch capType {
	case device.CapPowerSwitch:
		if value == true {
			return map[string]any{"state": "ON"}, nil
		}
		return map[string]any{"state": "OFF"}, nil
	case device.CapBrightness:
		v, ok := value.(float64)
		if !ok {
			if i, iok := value.(int); iok {
				v, ok = float64(i), true
			}
		}
		if !ok {
			return nil, fmt.Errorf("brightness value %v not numeric", value)
		}
		return map[string]any{"brightness": int(v/100*z2mBrightnessMax + 0.5)}, nil
	case device.CapColorRgb:
		rgb, ok := value.([]any)
		if !ok || len(rgb) != 3 {
			return nil, fmt.Errorf("colorRgb value %v not [r,g,b]", value)
		}
		return map[string]any{"color": map[string]any{
			"r": rgb[0], "g": rgb[1], "b": rgb[2]}}, nil
	case device.CapColorTemperature:
		return map[string]any{"color_temp": value}, nil
	case device.CapTargetTemperature:
		return map[string]any{"occupied_heating_setpoint": value}, nil
	default:
		return nil, fmt.Errorf("no z2m mapping for capability %s", capType)
	}
}

func numOr(v any, fallback float64) float64 {
	if f, ok := v.(float64); ok {
		return f
	}
	return fallback
}
