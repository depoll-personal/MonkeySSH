package main

import (
	"bytes"
	"io"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
)

type recordingConn struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (c *recordingConn) Read([]byte) (int, error) {
	return 0, io.EOF
}

func (c *recordingConn) Write(data []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.buf.Write(data)
}

func (c *recordingConn) Close() error {
	return nil
}

func (c *recordingConn) LocalAddr() net.Addr {
	return testAddr("local")
}

func (c *recordingConn) RemoteAddr() net.Addr {
	return testAddr("remote")
}

func (c *recordingConn) SetDeadline(time.Time) error {
	return nil
}

func (c *recordingConn) SetReadDeadline(time.Time) error {
	return nil
}

func (c *recordingConn) SetWriteDeadline(time.Time) error {
	return nil
}

func (c *recordingConn) String() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.buf.String()
}

func (c *recordingConn) Reset() {
	c.mu.Lock()
	c.buf.Reset()
	c.mu.Unlock()
}

func registerTestAttachClient(
	t testing.TB,
	server *muxServer,
	conn net.Conn,
	clientID string,
	width int,
	height int,
) *attachClient {
	t.Helper()
	client := newAttachClient(
		conn,
		controlMessage{
			ClientID: clientID,
			Width:    width,
			Height:   height,
		},
	)
	client.focusSequenceSnapshot = server.focusSequenceSnapshot
	client.focusClaim = func(expectedFocusSequence uint64) {
		server.focusAttachClientIfUnchanged(client, expectedFocusSequence)
	}
	server.mu.Lock()
	server.nextAttachSequence++
	client.sequence = server.nextAttachSequence
	server.nextFocusSequence++
	client.focusSequence.Store(server.nextFocusSequence)
	server.attachClients[conn] = client
	server.attachConn = conn
	if width > 0 {
		server.width = width
	}
	if height > 0 {
		server.height = height
	}
	server.mu.Unlock()
	t.Cleanup(client.close)
	return client
}

func waitForRecordedOutput(t *testing.T, conn *recordingConn, want string) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if got := conn.String(); got == want {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("recorded output = %q, want %q", conn.String(), want)
}

func waitForRecordedContains(
	t *testing.T,
	conn *recordingConn,
	want string,
) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if strings.Contains(conn.String(), want) {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("recorded output = %q, want it to contain %q", conn.String(), want)
}

type testAddr string

func (a testAddr) Network() string {
	return string(a)
}

func (a testAddr) String() string {
	return string(a)
}

func readSessionPID(session string) int {
	path, err := sessionPIDPath(session)
	if err != nil {
		return 0
	}
	return readPIDFileOrZero(path)
}

func newMuxServer(session string) *muxServer {
	return newMuxServerWithSize(session, defaultColumns, defaultRows)
}

func (w *muxWindow) historyTailLocked() []byte {
	history, _ := w.historyTailWithParserLocked()
	return history
}

func trimReplayHistoryForAttach(history []byte) []byte {
	return trimReplayHistoryForAttachWithParser(
		history,
		terminalOutputParserSnapshot{},
	)
}

func waitForTestAttachWrites(t *testing.T, server *muxServer) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		pending := false
		server.mu.Lock()
		for _, client := range server.attachClients {
			client.queueMu.Lock()
			pending = pending || client.queuedBytes != 0
			client.queueMu.Unlock()
		}
		server.mu.Unlock()
		if !pending {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("attach writes did not finish")
}

func waitForPendingQueryState(
	t *testing.T,
	server *muxServer,
	window *muxWindow,
	inFlight string,
	pending string,
) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		server.mu.Lock()
		gotInFlight := string(window.pendingTerminalQueriesInFlight)
		gotPending := string(window.pendingTerminalQueries)
		server.mu.Unlock()
		if gotInFlight == inFlight && gotPending == pending {
			return
		}
		time.Sleep(time.Millisecond)
	}
	server.mu.Lock()
	gotInFlight := string(window.pendingTerminalQueriesInFlight)
	gotPending := string(window.pendingTerminalQueries)
	server.mu.Unlock()
	t.Fatalf(
		"query state = in-flight %q, pending %q; want %q and %q",
		gotInFlight,
		gotPending,
		inFlight,
		pending,
	)
}
