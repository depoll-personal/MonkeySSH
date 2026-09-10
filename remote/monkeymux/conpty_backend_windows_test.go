//go:build windows

package main

import (
	"bytes"
	"encoding/hex"
	"errors"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf16"

	"golang.org/x/sys/windows"
)

const conPtyHelperEnvironment = "MONKEYMUX_CONPTY_TEST_HELPER=1"

const conPtyBracketedPasteHelperEnvironment = "MONKEYMUX_CONPTY_BRACKETED_PASTE_TEST_HELPER=1"

const conPtyTestRawAPC = "\x1b_Gi=31,a=T,t=d,f=24,s=1,v=1,c=1,r=12;AAAA\x1b\\"

const conPtyTestTmuxDCS = "\x1bPtmux;\x1b\x1b_Gi=32,a=T,t=d,f=24,s=1,v=1,c=1,r=12;AAAA" +
	"\x1b\x1b\\\x1b\\"

func TestBundledConPtyPreservesKittyGraphics(t *testing.T) {
	if os.Getenv("MONKEYMUX_CONPTY_TEST_HELPER") == "1" {
		runConPtyTestHelper()
		os.Exit(0)
	}

	backend := loadTestConPtyBackend(t)
	commandLine := conPtyTestCommand(t)
	env := append(os.Environ(), conPtyHelperEnvironment)
	writeHandle, readHandle, hpcon, processHandle, _, err :=
		startConPtyWithBackend(
			backend,
			commandLine,
			env,
			"",
			120,
			40,
		)
	if err != nil {
		t.Fatalf("start helper under bundled ConPTY: %v", err)
	}
	consoleFixture := ownTestConPty(t, backend, writeHandle, readHandle, hpcon, processHandle)
	data := consoleFixture.finish(true)
	got := string(data)
	for _, expected := range []string{
		conPtyTestRawAPC,
		conPtyTestTmuxDCS,
		"SENTINEL_END",
	} {
		if !strings.Contains(got, expected) {
			t.Errorf("bundled ConPTY output does not contain %q; output=%q", expected, got)
		}
	}
}

func TestBundledConPtyPreservesBracketedPasteInWin32InputMode(t *testing.T) {
	if os.Getenv("MONKEYMUX_CONPTY_BRACKETED_PASTE_TEST_HELPER") == "1" {
		runConPtyBracketedPasteTestHelper()
		os.Exit(0)
	}

	backend := loadTestConPtyBackend(t)
	commandLine := conPtyTestCommand(t)
	env := append(os.Environ(), conPtyBracketedPasteHelperEnvironment)
	writeHandle, readHandle, hpcon, processHandle, _, err :=
		startConPtyWithBackend(
			backend,
			commandLine,
			env,
			"",
			120,
			40,
		)
	if err != nil {
		t.Fatalf("start helper under bundled ConPTY: %v", err)
	}
	consoleFixture := ownTestConPty(t, backend, writeHandle, readHandle, hpcon, processHandle)
	select {
	case <-consoleFixture.ready:
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for bundled ConPTY helper readiness")
	}
	const paste = "\x1b[200~hello\x1b[201~!"
	if _, err := consoleFixture.input.Write(encodeBracketedPasteInputForWin32InputMode([]byte(paste))); err != nil {
		t.Fatalf("write bracketed paste: %v", err)
	}
	data := consoleFixture.finish(true)
	want := "INPUT_HEX:" + hex.EncodeToString([]byte(paste))
	if got := string(data); !strings.Contains(got, want) {
		t.Fatalf("bundled ConPTY input does not contain %q; output=%q", want, got)
	}
}

func TestConPtyRejectsInvalidInputBeforeCreate(t *testing.T) {
	backend := &conPtyBackend{create: func(windows.Coord, windows.Handle, windows.Handle, uint32, *windows.Handle) error {
		t.Error("invalid input reached pseudoconsole creation")
		return windows.ERROR_INVALID_PARAMETER
	}}
	for _, test := range []struct {
		command, dir string
		env          []string
		want         string
	}{
		{"cmd\x00", "", nil, "encode command line:"},
		{"cmd", "dir\x00", nil, "encode working directory:"},
		{"cmd", "", []string{"KEY=value\x00"}, "encode environment:"},
	} {
		t.Run(test.want, func(t *testing.T) {
			write, read, console, process, pid, err := startConPtyWithBackend(backend, test.command, test.env, test.dir, 80, 24)
			if err == nil || !strings.HasPrefix(err.Error(), test.want) {
				t.Fatalf("start error = %v, want %s", err, test.want)
			}
			if write != 0 || read != 0 || console != 0 || process != 0 || pid != 0 {
				t.Fatalf("failure returned resources: %v %v %v %v %v", write, read, console, process, pid)
			}
		})
	}
}

func TestConPtyStartFallsBackAndReturnsActualBackend(t *testing.T) {
	if os.Getenv("MONKEYMUX_CONPTY_TEST_HELPER") == "1" {
		runConPtyTestHelper()
		os.Exit(0)
	}

	fallback := loadTestConPtyBackend(t)
	closed := 0
	closeConsole := fallback.close
	fallback.close = func(handle windows.Handle) {
		closed++
		closeConsole(handle)
	}
	write, read, console, process, pid, startErr := startConPtyWithBackend(fallback, `"`+t.TempDir()+`\missing.exe"`, nil, "", 80, 24)
	if startErr == nil || !strings.HasPrefix(startErr.Error(), "create process:") {
		t.Fatalf("missing executable error = %v", startErr)
	}
	if write != 0 || read != 0 || console != 0 || process != 0 || pid != 0 || closed != 1 {
		t.Fatalf("failed launch resources = %v %v %v %v %v, console closes = %d", write, read, console, process, pid, closed)
	}
	preferred := &conPtyBackend{
		name: "injected-failure",
		create: func(
			windows.Coord,
			windows.Handle,
			windows.Handle,
			uint32,
			*windows.Handle,
		) error {
			return windows.ERROR_INVALID_PARAMETER
		},
	}
	commandLine := conPtyTestCommand(t)
	env := append(os.Environ(), conPtyHelperEnvironment)

	writeHandle, readHandle, hpcon, usedBackend, processHandle, _, err :=
		startConPtyWithFallback(
			preferred,
			fallback,
			commandLine,
			env,
			"",
			120,
			40,
		)
	if err != nil {
		t.Fatalf("start with fallback: %v", err)
	}
	consoleFixture := ownTestConPty(t, usedBackend, writeHandle, readHandle, hpcon, processHandle)
	if usedBackend != fallback {
		t.Fatalf("used backend = %q, want fallback %q", usedBackend.name, fallback.name)
	}
	consoleFixture.finish(true)
}

func runConPtyTestHelper() {
	stdout, err := windows.GetStdHandle(windows.STD_OUTPUT_HANDLE)
	if err == nil {
		var mode uint32
		if windows.GetConsoleMode(stdout, &mode) == nil {
			_ = windows.SetConsoleMode(
				stdout,
				mode|windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING,
			)
		}
	}
	_, _ = os.Stdout.WriteString(
		"BEGIN\r\n" +
			conPtyTestRawAPC + "AFTER_APC\r\n" +
			conPtyTestTmuxDCS + "AFTER_DCS\r\n" +
			"SENTINEL_END\r\n",
	)
	time.Sleep(100 * time.Millisecond)
}

func runConPtyBracketedPasteTestHelper() {
	stdout, err := windows.GetStdHandle(windows.STD_OUTPUT_HANDLE)
	if err == nil {
		var mode uint32
		if windows.GetConsoleMode(stdout, &mode) == nil {
			_ = windows.SetConsoleMode(
				stdout,
				mode|windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING,
			)
		}
	}
	stdin, err := windows.GetStdHandle(windows.STD_INPUT_HANDLE)
	if err != nil {
		os.Exit(2)
	}
	var inputMode uint32
	if windows.GetConsoleMode(stdin, &inputMode) == nil {
		inputMode &^= windows.ENABLE_LINE_INPUT |
			windows.ENABLE_ECHO_INPUT |
			windows.ENABLE_PROCESSED_INPUT
		_ = windows.SetConsoleMode(stdin, inputMode)
	}
	_, _ = os.Stdout.WriteString("\x1b[?9001h\x1b[?2004hREADY\r\n")

	var received []uint16
	buffer := make([]uint16, 64)
	for {
		var count uint32
		if err := windows.ReadConsole(
			stdin,
			&buffer[0],
			uint32(len(buffer)),
			&count,
			nil,
		); err != nil {
			os.Exit(3)
		}
		received = append(received, buffer[:count]...)
		if count > 0 && buffer[count-1] == '!' {
			break
		}
	}
	_, _ = os.Stdout.WriteString(
		"INPUT_HEX:" +
			hex.EncodeToString([]byte(string(utf16.Decode(received)))) +
			"\r\n",
	)
}

func loadTestConPtyBackend(t *testing.T) *conPtyBackend {
	t.Helper()
	previous := conPtyCacheRoot
	conPtyCacheRoot = t.TempDir()
	t.Cleanup(func() { conPtyCacheRoot = previous })
	backend, err := loadBundledConPtyBackend()
	if err != nil {
		t.Fatalf("load bundled ConPTY: %v", err)
	}
	t.Cleanup(func() {
		if backend.dll != nil {
			_ = windows.FreeLibrary(windows.Handle(backend.dll.Handle()))
		}
	})
	if backend.name != "bundled" {
		t.Fatalf("backend name = %q, want bundled", backend.name)
	}
	return backend
}

func conPtyTestCommand(t *testing.T) string {
	t.Helper()
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	return windows.ComposeCommandLine([]string{executable, "-test.run=^" + t.Name() + "$"})
}

type testConPty struct {
	input  *os.File
	ready  <-chan struct{}
	finish func(bool) []byte
}

func ownTestConPty(t *testing.T, backend *conPtyBackend, write, read, console, process windows.Handle) *testConPty {
	t.Helper()
	input := os.NewFile(uintptr(write), "conpty-test-input")
	output := os.NewFile(uintptr(read), "conpty-test-output")
	ready := make(chan struct{})
	drained := make(chan []byte, 1)
	var once sync.Once
	var data []byte
	fixture := &testConPty{input: input, ready: ready}
	fixture.finish = func(wait bool) []byte {
		t.Helper()
		once.Do(func() {
			var timeout uint32
			if wait {
				timeout = 10_000
			}
			result, err := windows.WaitForSingleObject(process, timeout)
			if wait && (err != nil || result != windows.WAIT_OBJECT_0) {
				t.Errorf("wait for ConPTY helper: result=%d, error=%v", result, err)
			}
			if err != nil || result != windows.WAIT_OBJECT_0 {
				if err := windows.TerminateProcess(process, 1); err != nil {
					t.Errorf("terminate helper: %v", err)
				}
				if result, err := windows.WaitForSingleObject(process, 5_000); err != nil || result != windows.WAIT_OBJECT_0 {
					t.Errorf("reap helper: result=%d, error=%v", result, err)
				}
			} else if wait {
				var exitCode uint32
				if err := windows.GetExitCodeProcess(process, &exitCode); err != nil || exitCode != 0 {
					t.Errorf("helper exit code = %d, error=%v", exitCode, err)
				}
			}
			// ClosePseudoConsole can block while flushing output. Keep draining
			// until the console is closed, then release the process and pipes.
			backend.close(console)
			_ = windows.CloseHandle(process)
			_ = input.Close()
			select {
			case data = <-drained:
			case <-time.After(5 * time.Second):
				t.Error("timed out draining ConPTY output")
				_ = output.Close()
				data = <-drained
			}
			_ = output.Close()
		})
		return data
	}
	t.Cleanup(func() { fixture.finish(false) })
	go func() {
		var data []byte
		buffer := make([]byte, 4096)
		readySent := false
		for {
			n, err := output.Read(buffer)
			data = append(data, buffer[:n]...)
			if !readySent && bytes.Contains(data, []byte("READY")) {
				close(ready)
				readySent = true
			}
			if err != nil {
				drained <- data
				return
			}
		}
	}()
	return fixture
}

func TestConPtyFixtureCleanupTerminatesUnfinishedChild(t *testing.T) {
	if os.Getenv("MONKEYMUX_CONPTY_BRACKETED_PASTE_TEST_HELPER") == "1" {
		runConPtyBracketedPasteTestHelper()
		os.Exit(0)
	}
	backend := loadTestConPtyBackend(t)
	command := conPtyTestCommand(t)
	closed := 0
	closeConsole := backend.close
	backend.close = func(handle windows.Handle) { closed++; closeConsole(handle) }
	var fixture *testConPty
	var process, observer windows.Handle
	t.Cleanup(func() { _ = windows.CloseHandle(observer) })
	t.Run("return before finish", func(t *testing.T) {
		write, read, console, child, _, err := startConPtyWithBackend(
			backend, command, append(os.Environ(), conPtyBracketedPasteHelperEnvironment), "", 120, 40,
		)
		if err != nil {
			t.Fatal(err)
		}
		fixture = ownTestConPty(t, backend, write, read, console, child)
		process = child
		if err := windows.DuplicateHandle(windows.CurrentProcess(), process, windows.CurrentProcess(), &observer, 0, false, windows.DUPLICATE_SAME_ACCESS); err != nil {
			t.Fatal(err)
		}
		select {
		case <-fixture.ready:
		case <-time.After(5 * time.Second):
			t.Fatal("helper did not become ready")
		}
		if result, err := windows.WaitForSingleObject(observer, 0); err != nil || result != uint32(windows.WAIT_TIMEOUT) {
			t.Fatalf("helper must still be waiting for input: result=%d, error=%v", result, err)
		}
		// Returning without finish exercises the same registered cleanup as Fatal.
	})
	if fixture == nil || observer == 0 {
		t.Fatal("helper fixture was not created")
	}
	fixture.finish(false)
	if closed != 1 {
		t.Errorf("console closed %d times, want once", closed)
	}
	if result, err := windows.WaitForSingleObject(observer, 0); err != nil || result != windows.WAIT_OBJECT_0 {
		t.Errorf("cleanup did not reap helper: result=%d, error=%v", result, err)
	}
	if _, err := windows.WaitForSingleObject(process, 0); err != windows.ERROR_INVALID_HANDLE {
		t.Errorf("process handle survived cleanup: %v", err)
	}
	if _, err := fixture.input.Write([]byte("late input")); !errors.Is(err, os.ErrClosed) {
		t.Errorf("input survived cleanup: %v", err)
	}
}
