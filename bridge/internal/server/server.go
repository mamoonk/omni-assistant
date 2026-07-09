// Package server hosts the Nexus WebSocket protocol endpoint.
package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/mamoonk/omni-assistant/bridge/internal/device"
	"github.com/mamoonk/omni-assistant/bridge/internal/manager"
	"github.com/mamoonk/omni-assistant/bridge/internal/protocol"
	"github.com/mamoonk/omni-assistant/bridge/internal/store"
)

const Version = "0.1.0"

var upgrader = websocket.Upgrader{
	// local-network service; the app connects from arbitrary origins
	CheckOrigin: func(*http.Request) bool { return true },
}

type Server struct {
	Name     string
	store    *store.Store
	managers map[string]manager.RadioManager // by protocol domain

	mu      sync.Mutex
	clients map[*client]struct{}
}

type client struct {
	conn *websocket.Conn
	send chan any
}

func New(name string, st *store.Store, managers ...manager.RadioManager) *Server {
	byDomain := map[string]manager.RadioManager{}
	for _, m := range managers {
		byDomain[m.Protocol()] = m
	}
	return &Server{
		Name:     name,
		store:    st,
		managers: byDomain,
		clients:  map[*client]struct{}{},
	}
}

// Run starts radio managers, fans their events out to clients, and persists
// interviewed devices. Blocks until ctx is done.
func (s *Server) Run(ctx context.Context) error {
	for _, m := range s.managers {
		if err := m.Start(ctx); err != nil {
			return err
		}
		go s.pumpEvents(ctx, m)
	}
	<-ctx.Done()
	for _, m := range s.managers {
		_ = m.Stop()
	}
	return nil
}

func (s *Server) pumpEvents(ctx context.Context, m manager.RadioManager) {
	for {
		select {
		case <-ctx.Done():
			return
		case e := <-m.Events():
			s.persistFromEvent(e)
			s.broadcast(e)
		}
	}
}

// persistFromEvent stores devices carried by interview/state events.
func (s *Server) persistFromEvent(e protocol.Event) {
	if e.Event != protocol.EvDeviceInterviewed && e.Event != protocol.EvStateChanged {
		return
	}
	data, ok := e.Data.(map[string]any)
	if !ok {
		return
	}
	raw, err := json.Marshal(data["device"])
	if err != nil {
		return
	}
	var d device.Device
	if err := json.Unmarshal(raw, &d); err != nil || d.ID == "" {
		return
	}
	if err := s.store.SaveDevice(d); err != nil {
		log.Printf("store: %v", err)
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", s.handleWS)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintln(w, "ok")
	})
	return mux
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	c := &client{conn: conn, send: make(chan any, 64)}
	s.mu.Lock()
	s.clients[c] = struct{}{}
	s.mu.Unlock()

	go c.writeLoop()
	s.readLoop(c)

	s.mu.Lock()
	delete(s.clients, c)
	s.mu.Unlock()
	close(c.send)
	conn.Close()
}

func (c *client) writeLoop() {
	for msg := range c.send {
		if err := c.conn.WriteJSON(msg); err != nil {
			return
		}
	}
}

func (s *Server) readLoop(c *client) {
	for {
		_, raw, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		var cmd protocol.Command
		if err := json.Unmarshal(raw, &cmd); err != nil || cmd.Type != "command" {
			continue
		}
		c.send <- s.Dispatch(cmd)
	}
}

// Dispatch executes one command and returns its result. Exported for tests.
func (s *Server) Dispatch(cmd protocol.Command) protocol.Result {
	switch cmd.Domain {
	case "bridge":
		return s.dispatchBridge(cmd)
	case "device":
		return s.dispatchDevice(cmd)
	default:
		if m, ok := s.managers[cmd.Domain]; ok {
			return s.dispatchRadio(m, cmd)
		}
		return protocol.Fail(cmd.ID, fmt.Errorf("unknown domain %q", cmd.Domain))
	}
}

func (s *Server) dispatchBridge(cmd protocol.Command) protocol.Result {
	switch cmd.Action {
	case "info":
		protocols := make([]string, 0, len(s.managers))
		for p := range s.managers {
			protocols = append(protocols, p)
		}
		return protocol.OK(cmd.ID, map[string]any{
			"name":      s.Name,
			"version":   Version,
			"protocols": protocols,
		})
	default:
		return protocol.Fail(cmd.ID, fmt.Errorf("unknown action %q", cmd.Action))
	}
}

func (s *Server) dispatchDevice(cmd protocol.Command) protocol.Result {
	switch cmd.Action {
	case "list":
		all := []any{}
		for _, m := range s.managers {
			for _, d := range m.Devices() {
				all = append(all, d)
			}
		}
		return protocol.OK(cmd.ID, map[string]any{"devices": all})

	case "execute":
		var p struct {
			DeviceID   string `json:"deviceId"`
			Capability string `json:"capability"`
			Value      any    `json:"value"`
		}
		if err := json.Unmarshal(cmd.Params, &p); err != nil {
			return protocol.Fail(cmd.ID, err)
		}
		for _, m := range s.managers {
			if err := m.Execute(p.DeviceID, p.Capability, p.Value); err == nil {
				return protocol.OK(cmd.ID, nil)
			}
		}
		return protocol.Fail(cmd.ID, fmt.Errorf("no manager accepted device %s", p.DeviceID))

	default:
		return protocol.Fail(cmd.ID, fmt.Errorf("unknown action %q", cmd.Action))
	}
}

func (s *Server) dispatchRadio(m manager.RadioManager, cmd protocol.Command) protocol.Result {
	switch cmd.Action {
	case "permit_join":
		var p struct {
			Duration int `json:"duration"`
		}
		if len(cmd.Params) > 0 {
			if err := json.Unmarshal(cmd.Params, &p); err != nil {
				return protocol.Fail(cmd.ID, err)
			}
		}
		if p.Duration <= 0 {
			p.Duration = 60
		}
		if err := m.PermitJoin(p.Duration); err != nil {
			return protocol.Fail(cmd.ID, err)
		}
		return protocol.OK(cmd.ID, map[string]any{"duration": p.Duration})
	default:
		return protocol.Fail(cmd.ID, fmt.Errorf("unknown action %q", cmd.Action))
	}
}

func (s *Server) broadcast(e protocol.Event) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for c := range s.clients {
		select {
		case c.send <- e:
		default: // slow client: drop event instead of blocking the pump
		}
	}
}
