// Nexus Bridge — standalone companion service for the Home Nexus app (§5).
// Hosts the Nexus WebSocket protocol, orchestrates radio managers, persists
// devices in BoltDB, and advertises itself over mDNS.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"

	"github.com/mamoonk/omni-assistant/bridge/internal/discovery"
	"github.com/mamoonk/omni-assistant/bridge/internal/manager"
	"github.com/mamoonk/omni-assistant/bridge/internal/server"
	"github.com/mamoonk/omni-assistant/bridge/internal/store"
)

func main() {
	port := flag.Int("port", 8927, "listen port")
	name := flag.String("name", "Nexus Bridge", "bridge name advertised on the network")
	dataDir := flag.String("data", defaultDataDir(), "data directory")
	demo := flag.Bool("demo", false, "simulate a Zigbee radio (no hardware needed)")
	noMdns := flag.Bool("no-mdns", false, "disable mDNS advertisement")
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
	if *demo {
		dm := manager.NewDemo("bridge0")
		if saved, err := st.Devices(); err == nil {
			dm.Seed(saved)
		}
		managers = append(managers, dm)
		log.Print("demo mode: simulated Zigbee radio active")
	} else {
		// TODO(phase3): Zigbee2MQTT / Z-Wave JS UI subprocess managers
		log.Print("no radio managers configured; run with -demo or attach hardware managers")
	}

	srv := server.New(*name, st, managers...)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	if !*noMdns {
		shutdown, err := discovery.Advertise(*name, *port, server.Version)
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

func defaultDataDir() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "."
	}
	return filepath.Join(dir, "nexus-bridge")
}
