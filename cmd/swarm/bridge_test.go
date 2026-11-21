package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// stubSwarm is a bin/swarm.sh that records what it was given, one line each: every argument in
// brackets (so an empty one shows), stdin, the cwd, SWARM_PROJECT and SWARM_GH_VIA. Then it writes one
// line to stdout and one to stderr, and exits 7.
const stubSwarm = `#!/usr/bin/env bash
{
  for a in "$@"; do printf 'arg [%s]\n' "$a"; done
  printf 'stdin [%s]\n' "$(cat)"
  printf 'cwd [%s]\n' "$(pwd -P)"
  printf 'project [%s]\n' "${SWARM_PROJECT-unset}"
  printf 'via [%s]\n' "${SWARM_GH_VIA-unset}"
} > "$(dirname "$0")/record"
echo "the stub's stdout"
echo "the stub's stderr" >&2
exit 7
`

// stubHome makes a plugin root whose bin/swarm.sh is stubSwarm, and returns it.
func stubHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "bin", "swarm.sh"), []byte(stubSwarm), 0o755); err != nil {
		t.Fatal(err)
	}
	return home
}

// withHome is the handoff with SWARMDEV_HOME set to home.
func withHome(home string) []string {
	env := handoff("", "")
	for i, kv := range env {
		if strings.HasPrefix(kv, envHome+"=") {
			env[i] = envHome + "=" + home
		}
	}
	return env
}

// If the bridge drops, reorders or joins an argument (the empty last one too), loses stdin, mixes the
// two streams, changes the exit code, sets no SWARM_PROJECT or leaves a stale one, drops SWARM_GH_VIA
// or runs from another cwd, this goes red.
func TestBridgeHandsTheFormToSwarmSh(t *testing.T) {
	home := stubHome(t)
	cwd := t.TempDir()
	t.Chdir(cwd)
	t.Setenv("SWARM_GH_VIA", "swarm.sh wrapper-fixture")
	t.Setenv("SWARM_PROJECT", "/a/stale/project")
	r := runFixture(t, withHome(home), "in one\nin two\n", "wrapper-fixture", "name", "a", "b c", "")
	if r.code != 7 || r.stdout != "the stub's stdout\n" || r.stderr != "the stub's stderr\n" {
		t.Errorf("the bash form: code %d, stdout %q, stderr %q; want 7, %q, %q",
			r.code, r.stdout, r.stderr, "the stub's stdout\n", "the stub's stderr\n")
	}
	realCwd, err := filepath.EvalSymlinks(cwd)
	if err != nil {
		t.Fatal(err)
	}
	want := strings.Join([]string{
		"arg [_name]", "arg [a]", "arg [b c]", "arg []",
		"stdin [in one\nin two]",
		"cwd [" + realCwd + "]",
		"project [/proj]",
		"via [swarm.sh wrapper-fixture]",
	}, "\n") + "\n"
	got, err := os.ReadFile(filepath.Join(home, "bin", "record"))
	if err != nil || string(got) != want {
		t.Errorf("the stub was given:\n%s(%v)\nwant:\n%s", got, err, want)
	}
}

// If the bridge runs with no plugin root, it would run a bin/swarm.sh relative to the cwd; this goes
// red when it does anything but refuse.
func TestBridgeRefusesWithNoHome(t *testing.T) {
	cwd := stubHome(t)
	t.Chdir(cwd)
	r := runFixture(t, withHome(""), "", "wrapper-fixture", "board-rel")
	want := "swarm: _board-rel: the frame names no plugin root (SWARMDEV_HOME), so there is no swarm.sh to run\n"
	if r.code != exitUsage || r.stdout != "" || r.stderr != want {
		t.Errorf("no home: code %d, stdout %q, stderr %q; want %d, nothing, %q", r.code, r.stdout, r.stderr, exitUsage, want)
	}
	if _, err := os.Stat(filepath.Join(cwd, "bin", "record")); err == nil {
		t.Errorf("no home: the cwd's bin/swarm.sh ran")
	}
}
