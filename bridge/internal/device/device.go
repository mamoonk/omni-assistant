// Package device mirrors the Flutter unification package's JSON shape so a
// bridge Device deserializes directly into a UniversalDevice.
package device

// Capability state maps carry everything needed to rebuild the typed
// capability on the app side ({type, state}).
type Capability struct {
	Type  string         `json:"type"`
	State map[string]any `json:"state"`
}

type Origin struct {
	Type         string `json:"type"` // always "nexusBridge"
	ConnectionID string `json:"connectionId"`
	NativeID     string `json:"nativeId"`
	Protocol     string `json:"protocol"` // zigbee, zwave, thread
}

type Device struct {
	ID           string       `json:"id"`
	Name         string       `json:"name"`
	Manufacturer string       `json:"manufacturer"`
	Model        string       `json:"model"`
	Origin       Origin       `json:"origin"`
	RoomID       string       `json:"roomId"`
	Capabilities []Capability `json:"capabilities"`
}

// Capability type constants — must match unification's CapabilityType.
const (
	CapPowerSwitch        = "powerSwitch"
	CapBrightness         = "brightness"
	CapColorRgb           = "colorRgb"
	CapColorTemperature   = "colorTemperature"
	CapTargetTemperature  = "targetTemperature"
	CapCurrentTemperature = "currentTemperature"
	CapHumidity           = "humidity"
	CapMotion             = "motion"
	CapContact            = "contact"
	CapBattery            = "battery"
)

// Find returns the capability with the given type, or nil.
func (d *Device) Find(capType string) *Capability {
	for i := range d.Capabilities {
		if d.Capabilities[i].Type == capType {
			return &d.Capabilities[i]
		}
	}
	return nil
}
