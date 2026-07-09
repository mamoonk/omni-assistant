// Package discovery advertises the bridge on the LAN via mDNS so the app
// finds it without manual IP entry.
package discovery

import (
	"github.com/grandcat/zeroconf"
)

const ServiceType = "_nexus-bridge._tcp"

// Advertise registers the service; call the returned shutdown func on exit.
func Advertise(name string, port int, version string) (func(), error) {
	server, err := zeroconf.Register(
		name,
		ServiceType,
		"local.",
		port,
		[]string{"version=" + version, "path=/ws"},
		nil,
	)
	if err != nil {
		return nil, err
	}
	return server.Shutdown, nil
}
