package main

import (
	"io"
	"strconv"
	"sync"
	"testing"
	"time"
)

// Model a differential renderer that only invalidates its entire frame when
// columns change. Height-only and same-size notifications are insufficient
// after MonkeyMux has cleared the attaching terminal.
type piRedrawPty struct {
	mu            sync.Mutex
	width, height int
	fullRedraws   int
}

func (p *piRedrawPty) Read([]byte) (int, error)    { return 0, io.EOF }
func (p *piRedrawPty) Write(b []byte) (int, error) { return len(b), nil }
func (p *piRedrawPty) Close() error                { return nil }
func (p *piRedrawPty) Fd() uintptr                 { return 0 }
func (p *piRedrawPty) Resize(w, h int) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if w != p.width {
		p.fullRedraws++
	}
	p.width, p.height = w, h
	return nil
}

func TestPiSwitchRedrawInvalidatesColumns(t *testing.T) {
	for _, width := range []int{120, 1} {
		t.Run(strconv.Itoa(width), func(t *testing.T) {
			pty := &piRedrawPty{width: width, height: 40}
			window := &muxWindow{id: "@1", foregroundCommand: "pi", pty: pty, ptyWidth: width, ptyHeight: 40}
			server := newMuxServerWithSize("test", width, 40)
			server.windows = []*muxWindow{window}
			server.activeID = window.id
			registerTestAttachClient(t, server, &recordingConn{}, "primary", width, 40)
			server.attachMu.Lock()
			redrew := server.broadcastAttachReplayAndResizeLocked([]byte(activeWindowReplayPrefix), window)
			server.attachMu.Unlock()
			if !redrew {
				t.Fatal("switch did not request a redraw")
			}
			deadline := time.Now().Add(time.Second)
			for time.Now().Before(deadline) {
				pty.mu.Lock()
				restored := pty.width == width && pty.height == 40 && pty.fullRedraws >= 2
				pty.mu.Unlock()
				if restored {
					return
				}
				time.Sleep(5 * time.Millisecond)
			}
			pty.mu.Lock()
			defer pty.mu.Unlock()
			t.Fatalf("switch left renderer at %dx%d with %d full redraws", pty.width, pty.height, pty.fullRedraws)
		})
	}
}

func TestPiSameSizeSettleRequestsSyntheticRedraw(t *testing.T) {
	for _, tc := range []struct {
		name  string
		width int
		force bool
		want  int
	}{
		{"forced settle", 120, true, 1},
		{"real resize", 100, true, 0},
		{"unchanged without redraw", 120, false, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := newMuxServerWithSize("test", 120, 40)
			window := &muxWindow{id: "@1", foregroundCommand: "pi"}
			server.windows = []*muxWindow{window}
			server.activeID = window.id
			original := simulateForegroundResize
			t.Cleanup(func() { simulateForegroundResize = original })
			calls := 0
			simulateForegroundResize = func(*muxWindow, int, int) { calls++ }
			server.resizeWithRedraw(tc.width, 40, tc.force, false, "")
			if calls != tc.want {
				t.Fatalf("synthetic redraws=%d, want %d", calls, tc.want)
			}
		})
	}
}
