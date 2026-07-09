// Nexus Bridge — standalone companion service for the Home Nexus app (§5).
// Hosts the Nexus WebSocket protocol, orchestrates radio managers, persists
// devices in BoltDB, and advertises itself over mDNS.
package main

import (
	"context"
	"crypto/rand"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"

	"github.com/mamoonk/omni-assistant/bridge/internal/discovery"
	"github.com/mamoonk/omni-assistant/bridge/internal/manager"
	"github.com/mamoonk/omni-assistant/bridge/internal/matter"
	"github.com/mamoonk/omni-assistant/bridge/internal/server"
	"github.com/mamoonk/omni-assistant/bridge/internal/store"
)

func main() {
	port := flag.Int("port", 8927, "listen port")
	name := flag.String("name", "Nexus Bridge", "bridge name advertised on the network")
	dataDir := flag.String("data", defaultDataDir(), "data directory")
	demo := flag.Bool("demo", false, "simulate a Zigbee radio (no hardware needed)")
	noMdns := flag.Bool("no-mdns", false, "disable mDNS advertisement")
	zigbee := flag.Bool("zigbee", false, "enable the Zigbee2MQTT manager")
	brokerAddr := flag.String("mqtt-listen", ":1884", "embedded MQTT broker listen address (for zigbee2mqtt)")
	baseTopic := flag.String("mqtt-base", "zigbee2mqtt", "zigbee2mqtt base topic")
	z2mCmd := flag.String("z2m-cmd", "", "command to launch zigbee2mqtt, e.g. \"node /opt/zigbee2mqtt/index.js\" (empty = externally managed)")
	chipTool := flag.String("chip-tool", "", "path to chip-tool for real Matter commissioning")
	token := flag.String("token", "", "pairing token clients must present (default: generated on first run and persisted)")
	noAuth := flag.Bool("no-auth", false, "disable client authentication (trusted networks only)")
	flag.Parse()

	if err := os.MkdirAll(*dataDir, 0o755); err != nil {
		log.Fatalf("data dir: %v", err)
	}
	st, err := store.Open(filepath.Join(*dataDir, "nexus.db"))
	if err != nil {
		log.Fatalf("store: %v", err)
	}
	defer st.Close()

	var managers []manager.RadioManager
	switch {
	case *demo:
		dm := manager.NewDemo("bridge0")
		if saved, err := st.Devices(); err == nil {
			dm.Seed(saved)
		}
		mm := matter.New("bridge0", true, "")
		if saved, err := st.Devices(); err == nil {
			mm.Seed(saved)
		}
		managers = append(managers, dm, mm)
		log.Print("demo mode: simulated Zigbee radio + Matter controller active")
	case *zigbee:
		var cmd []string
		if *z2mCmd != "" {
			cmd = strings.Fields(*z2mCmd)
		}
		managers = append(managers, manager.NewZ2M(manager.Z2MOptions{
			ConnectionID: "bridge0",
			BrokerAddr:   *brokerAddr,
			BaseTopic:    *baseTopic,
			Z2MCommand:   cmd,
		}))
		log.Printf("zigbee: embedded MQTT broker on %s (base topic %q)",
			*brokerAddr, *baseTopic)
		if *z2mCmd == "" {
			log.Print("zigbee: point your zigbee2mqtt at this broker, or pass -z2m-cmd to have the bridge manage it")
		}
		if *chipTool != "" {
			mm := matter.New("bridge0", false, *chipTool)
			if saved, err := st.Devices(); err == nil {
				mm.Seed(saved)
			}
			managers = append(managers, mm)
			log.Printf("matter: commissioning via %s", *chipTool)
		}
	default:
		log.Print("no radio managers configured; run with -demo or -zigbee")
	}

	srv := server.New(*name, st, managers...)
	if !*noAuth {
		pairingToken := *token
		if pairingToken == "" {
			saved, _ := st.Config("pairing_token")
			if saved == "" {
				saved = generateToken()
				if err := st.SetConfig("pairing_token", saved); err != nil {
					log.Fatalf("persist token: %v", err)
				}
			}
			pairingToken = saved
		} else {
			_ = st.SetConfig("pairing_token", pairingToken)
		}
		srv.Token = pairingToken
		log.Printf("pairing token: %s  (enter this in the app; -no-auth disables)", pairingToken)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	if !*noMdns {
		instanceID, _ := st.Config("instance_id")
		if instanceID == "" {
			instanceID = generateToken()
			_ = st.SetConfig("instance_id", instanceID)
		}
		shutdown, err := discovery.Advertise(
			*name, *port, server.Version, instanceID, srv.Token != "")
		if err != nil {
			log.Printf("mdns disabled: %v", err)
		} else {
			defer shutdown()
		}
	}

	httpServer := &http.Server{
		Addr:    fmt.Sprintf(":%d", *port),
		Handler: srv.Handler(),
	}
	go func() {
		<-ctx.Done()
		httpServer.Close()
	}()
	go func() {
		if err := srv.Run(ctx); err != nil {
			log.Printf("server: %v", err)
		}
	}()

	log.Printf("%s listening on ws://0.0.0.0:%d/ws", *name, *port)
	if err := httpServer.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func generateToken() string {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("token generation: %v", err)
	}
	return fmt.Sprintf("%08x", b)
}

func defaultDataDir() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "."
	}
	return filepath.Join(dir, "nexus-bridge")
}
