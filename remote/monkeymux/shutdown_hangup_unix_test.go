//go:build !windows

package main

import (
	"os/exec"
	"testing"
	"time"
)

// A pane's interactive shell runs its jobs under job control, so the agent
// sits in its own process group as the terminal's foreground group. An agent
// that ignores SIGHUP (cursor-agent does) then survives both the terminal
// hangup and a kill of the shell's group, its watcher never finishes, close
// runs out its whole bound, and the replacement helper's exit wait times out:
// no helper update can ever replace the server (seen live during a forced
// reload). Shutdown must kill the foreground group too.
func TestCloseKillsForegroundGroupThatIgnoresHangup(t *testing.T) {
	cmd := exec.Command("/bin/sh", "-c", `set -m; trap "" HUP; sleep 30`)
	windowPty, proc, err := startWindow(cmd, 80, 24)
	if err != nil {
		t.Fatal(err)
	}
	window := &muxWindow{proc: proc, pty: windowPty}
	t.Cleanup(func() {
		if group := foregroundProcessGroupForWindow(window); group > 0 {
			killProcessGroup(group)
		}
		proc.Kill()
		_ = windowPty.Close()
	})
	// Mirror the server: one goroutine reads the pty, another reaps the child.
	go func() {
		buf := make([]byte, 1024)
		for {
			if _, err := windowPty.Read(buf); err != nil {
				return
			}
		}
	}()
	waited := make(chan struct{})
	go func() { _ = proc.Wait(); close(waited) }()
	// Let the shell install its trap and start the job in its own group.
	var group int
	for start := time.Now(); time.Since(start) < 3*time.Second; time.Sleep(20 * time.Millisecond) {
		if group = foregroundProcessGroupForWindow(window); group > 0 && group != proc.Pid() {
			break
		}
	}
	if group <= 0 || group == proc.Pid() {
		t.Fatalf("job did not become its own foreground group (group %d, shell %d)", group, proc.Pid())
	}
	time.Sleep(100 * time.Millisecond)

	start := time.Now()
	groups := shutdownForegroundGroups([]*muxWindow{window})
	proc.Hangup()
	if err := windowPty.Close(); err != nil {
		t.Fatal(err)
	}
	killSurvivingWindowProcesses([]*muxWindow{window}, groups, 300*time.Millisecond)
	select {
	case <-waited:
	case <-time.After(2 * time.Second):
		t.Fatal("shell survived hangup and kill escalation")
	}
	deadline := time.Now().Add(2 * time.Second)
	for processIDAlive(group) && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if processIDAlive(group) {
		t.Fatalf("foreground job %d survived shutdown", group)
	}
	if elapsed := time.Since(start); elapsed > 1500*time.Millisecond {
		t.Fatalf("shutdown took %v, want under the exit wait budget", elapsed)
	}
}

func TestKillSurvivingWindowProcessesSkipsExitedChildren(t *testing.T) {
	cmd := exec.Command("/bin/sh", "-c", "exit 0")
	windowPty, proc, err := startWindow(cmd, 80, 24)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = windowPty.Close() })
	if err := proc.Wait(); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	killSurvivingWindowProcesses([]*muxWindow{{proc: proc}, {}}, nil, time.Second)
	if elapsed := time.Since(start); elapsed > 500*time.Millisecond {
		t.Fatalf("waited %v for an already-exited child", elapsed)
	}
}
