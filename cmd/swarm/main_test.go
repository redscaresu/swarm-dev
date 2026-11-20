package main

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"testing"
)

// runMainEnv names the variable that makes TestMain call main() in place of the tests, so a test can
// run this test binary as the command itself.
const runMainEnv = "SWARM_TEST_RUN_MAIN"

// wantLine and wantCode are written out here, not taken from main.go, so a change there goes red.
const (
	wantLine = "swarm: no command is ported yet\n"
	wantCode = 2
)

func TestMain(m *testing.M) {
	if os.Getenv(runMainEnv) == "1" {
		main()
		// main() must exit; reaching here means it returned.
		os.Exit(99)
	}
	os.Exit(m.Run())
}

func TestRunPrintsNotPortedAndExits2(t *testing.T) {
	var stderr bytes.Buffer
	if got := run([]string{"next"}, &stderr); got != wantCode {
		t.Errorf("run() = %d, want %d", got, wantCode)
	}
	if got := stderr.String(); got != wantLine {
		t.Errorf("run() wrote %q on stderr, want %q", got, wantLine)
	}
}

// TestMainExitsWithRunsCode runs the test binary as the command, so a main() that drops run()'s
// result, or writes anything on stdout, goes red.
func TestMainExitsWithRunsCode(t *testing.T) {
	cmd := exec.Command(os.Args[0], "next")
	cmd.Env = append(os.Environ(), runMainEnv+"=1")
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	var exitErr *exec.ExitError
	switch {
	case err == nil:
		t.Errorf("main() exited 0, want %d", wantCode)
	case errors.As(err, &exitErr):
		if got := exitErr.ExitCode(); got != wantCode {
			t.Errorf("main() exited %d, want %d", got, wantCode)
		}
	default:
		t.Fatalf("running %s: %v", os.Args[0], err)
	}
	if got := stdout.String(); got != "" {
		t.Errorf("main() wrote %q on stdout, want nothing", got)
	}
	if got := stderr.String(); got != wantLine {
		t.Errorf("main() wrote %q on stderr, want %q", got, wantLine)
	}
}
