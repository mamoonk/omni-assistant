package server

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"
	"time"

	"github.com/mamoonk/omni-assistant/bridge/internal/manager"
	"github.com/mamoonk/omni-assistant/bridge/internal/protocol"
	"github.com/mamoonk/omni-assistant/bridge/internal/store"
)

func newTestServer(t *testing.T) (*Server, *manager.DemoManager) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })

	dm := manager.NewDemo("test")
	dm.JoinDelay = 10 * time.Millisecond
	dm.InterviewDelay = 10 * time.Millisecond

	s := New("Test Bridge", st, dm)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go s.Run(ctx)
	return s, dm
}

func cmd(t *testing.T, id, domain, action string, params any) protocol.Command {
	t.Helper()
	var raw json.RawMessage
	if params != nil {
		b, err := json.Marshal(params)
		if err != nil {
			t.Fatal(err)
		}
		raw = b
	}
	return protocol.Command{ID: id, Type: "command", Domain: domain, Action: action, Params: raw}
}

func TestBridgeInfo(t *testing.T) {
	s, _ := newTestServer(t)
	res := s.Dispatch(cmd(t, "1", "bridge", "info", nil))
	if !res.Success {
		t.Fatalf("info failed: %s", res.Error)
	}
	info := res.Result.(map[string]any)
	if info["name"] != "Test Bridge" {
		t.Errorf("name = %v", info["name"])
	}
}

func TestPermitJoinProducesInterviewedDevice(t *testing.T) {
	s, dm := newTestServer(t)

	res := s.Dispatch(cmd(t, "2", "zigbee", "permit_join", map[string]int{"duration": 30}))
	if !res.Success {
		t.Fatalf("permit_join failed: %s", res.Error)
	}

	deadline := time.After(2 * time.Second)
	for {
		if len(dm.Devices()) == 1 {
			break
		}
		select {
		case <-deadline:
			t.Fatal("no device joined within deadline")
		case <-time.After(10 * time.Millisecond):
		}
	}

	list := s.Dispatch(cmd(t, "3", "device", "list", nil))
	devices := list.Result.(map[string]any)["devices"].([]any)
	if len(devices) != 1 {
		t.Fatalf("device list = %d, want 1", len(devices))
	}
}

func TestExecuteMutatesState(t *testing.T) {
	s, dm := newTestServer(t)
	s.Dispatch(cmd(t, "1", "zigbee", "permit_join", nil))

	deadline := time.After(2 * time.Second)
	for len(dm.Devices()) == 0 {
		select {
		case <-deadline:
			t.Fatal("no device joined")
		case <-time.After(10 * time.Millisecond):
		}
	}

	d := dm.Devices()[0]
	res := s.Dispatch(cmd(t, "2", "device", "execute", map[string]any{
		"deviceId":   d.ID,
		"capability": "powerSwitch",
		"value":      true,
	}))
	if !res.Success {
		t.Fatalf("execute failed: %s", res.Error)
	}
	if on := dm.Devices()[0].Find("powerSwitch").State["on"]; on != true {
		t.Errorf("power state = %v, want true", on)
	}
}

func TestUnknownDomainFails(t *testing.T) {
	s, _ := newTestServer(t)
	if res := s.Dispatch(cmd(t, "1", "nope", "x", nil)); res.Success {
		t.Error("expected failure for unknown domain")
	}
}
