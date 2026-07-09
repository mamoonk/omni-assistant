package manager

import (
	"context"
	"log"
	"os/exec"
	"time"
)

// Supervisor keeps a child process (Zigbee2MQTT, Z-Wave JS UI) running,
// restarting it with capped exponential backoff until the context ends.
type Supervisor struct {
	Name    string
	Command []string // argv; empty disables the supervisor

	// MaxBackoff caps the restart delay (default 60s).
	MaxBackoff time.Duration
}

// Run blocks until ctx is done. Restarts the process whenever it exits.
func (s *Supervisor) Run(ctx context.Context) {
	if len(s.Command) == 0 {
		return
	}
	maxBackoff := s.MaxBackoff
	if maxBackoff == 0 {
		maxBackoff = 60 * time.Second
	}
	backoff := time.Second

	for {
		start := time.Now()
		cmd := exec.CommandContext(ctx, s.Command[0], s.Command[1:]...)
		log.Printf("%s: starting %v", s.Name, s.Command)
		err := cmd.Run()
		if ctx.Err() != nil {
			return
		}
		log.Printf("%s: exited (%v), restarting in %s", s.Name, err, backoff)

		// a process that survived a while earns a reset backoff
		if time.Since(start) > 30*time.Second {
			backoff = time.Second
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		if backoff *= 2; backoff > maxBackoff {
			backoff = maxBackoff
		}
	}
}
