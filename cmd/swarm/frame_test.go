package main

import (
	"bytes"
	"errors"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
)

// portedDir is bin/ported/ from this package's directory, where go test runs.
const portedDir = "../../bin/ported"

// recordingStore is the real store, with each path it is asked to write recorded.
type recordingStore struct {
	store.Files
	paths []string
}

func (s *recordingStore) WriteLine(path, line string) error {
	s.paths = append(s.paths, path)
	return s.Files.WriteLine(path, line)
}

func (s *recordingStore) AppendLines(path string, lines []string) error {
	s.paths = append(s.paths, path)
	return s.Files.AppendLines(path, lines)
}

// result is what one run left.
type result struct {
	code           int
	stdout, stderr string
	writes         []string
}

// runFixture runs args through the real table with environ as the frame and stdin as its input.
func runFixture(t *testing.T, environ []string, stdin string, args ...string) result {
	t.Helper()
	var stdout, stderr bytes.Buffer
	st := &recordingStore{}
	c := &call{stdin: strings.NewReader(stdin), stdout: &stdout, stderr: &stderr, frame: readFrame(environ), store: st}
	code := run(entries, args, c)
	return result{code: code, stdout: stdout.String(), stderr: stderr.String(), writes: st.paths}
}

// handoff is a frame as bin/swarm.sh hands it over, with dieFile and fieldsFile as given.
func handoff(dieFile, fieldsFile string) []string {
	return []string{
		"PATH=/usr/bin",
		"SWARMDEV_HOME=/plugin", "SWARMDEV_PROJECT=/proj", "SWARMDEV_BOARD=/proj/docs",
		"SWARMDEV_DIE_FILE=" + dieFile, "SWARMDEV_FIELDS_FILE=" + fieldsFile,
		"SWARMDEV_CFG_merge=agent", "SWARMDEV_SRC_merge=config",
		"SWARMDEV_CFG_board_dir=/proj/docs", "SWARMDEV_SRC_board_dir=default",
		"SWARMDEV_CFG_goal=", "SWARMDEV_SRC_goal=default",
		"SWARMDEV_CFG_zz_new_key=a = b", "SWARMDEV_SRC_zz_new_key=config",
	}
}

// If the fixture drops a frame value, a setting the binary keeps no list for, an argument or stdin,
// or prints them out of order, this goes red.
func TestFixturePrintsTheFrame(t *testing.T) {
	r := runFixture(t, handoff("", ""), "one\ntwo\n", "wrapper-fixture", "x", "y z")
	want := strings.Join([]string{
		"project = /proj", "board = /proj/docs", "home = /plugin",
		"arg = x", "arg = y z",
		"stdin = one", "stdin = two",
		"board_dir = /proj/docs    (default)",
		"goal =     (default)",
		"merge = agent    (config)",
		"zz_new_key = a = b    (config)",
	}, "\n") + "\n"
	if r.code != 0 || r.stdout != want || r.stderr != "" {
		t.Errorf("wrapper-fixture with the frame: code %d, stdout %q, stderr %q; want 0, %q, nothing", r.code, r.stdout, r.stderr, want)
	}
}

// If an entry that needs the frame runs without it, or says more than one line, this goes red.
func TestFixtureRefusesWithoutTheFrame(t *testing.T) {
	env := slices.DeleteFunc(handoff("", ""), func(kv string) bool { return strings.HasPrefix(kv, envProject+"=") })
	r := runFixture(t, env, "", "wrapper-fixture")
	want := "swarm: wrapper-fixture needs the frame bin/swarm.sh sets up: run it through bin/swarm.sh\n"
	if r.code != 2 || r.stdout != "" || r.stderr != want {
		t.Errorf("wrapper-fixture with no project: code %d, stdout %q, stderr %q; want 2, nothing, %q", r.code, r.stdout, r.stderr, want)
	}
}

// If a failure stops writing its first line to the die file, writes the prefix there, or loses its
// code, this goes red; so does a run that writes a file when the die file is empty.
func TestFixtureFailsAsDieDoes(t *testing.T) {
	dieFile := filepath.Join(t.TempDir(), "die")
	r := runFixture(t, handoff(dieFile, ""), "", "wrapper-fixture", "--fail", "3", "--line", "L went wrong\nsecond line")
	if r.code != 3 || r.stderr != "swarm: L went wrong\nsecond line\n" {
		t.Errorf("--fail 3: code %d, stderr %q; want 3, %q", r.code, r.stderr, "swarm: L went wrong\nsecond line\n")
	}
	if got, err := os.ReadFile(dieFile); err != nil || string(got) != "L went wrong\n" {
		t.Errorf("--fail 3: the die file holds %q (%v), want %q", got, err, "L went wrong\n")
	}

	r = runFixture(t, handoff("", ""), "", "wrapper-fixture", "--fail", "3", "--line", "L")
	if r.code != 3 || r.stderr != "swarm: L\n" || len(r.writes) != 0 {
		t.Errorf("--fail 3 with no die file: code %d, stderr %q, wrote %q; want 3, %q, no file", r.code, r.stderr, r.writes, "swarm: L\n")
	}
}

// If a failure with no line prints one or writes the die file, the wrapper's 'failed (exit N)'
// outcome is lost, and this goes red.
func TestFixtureFailsWithNoLine(t *testing.T) {
	dieFile := filepath.Join(t.TempDir(), "die")
	r := runFixture(t, handoff(dieFile, ""), "", "wrapper-fixture", "--fail", "3")
	if r.code != 3 || r.stderr != "" || len(r.writes) != 0 {
		t.Errorf("--fail 3 with no line: code %d, stderr %q, wrote %q; want 3, nothing, no file", r.code, r.stderr, r.writes)
	}
}

// If the fields stop reaching the fields file in event_fields' form, this goes red.
func TestFixtureWritesFields(t *testing.T) {
	fields := filepath.Join(t.TempDir(), "fields")
	r := runFixture(t, handoff("", fields), "", "wrapper-fixture", "--field", "pr=a b\tc", "--field", "empty=")
	got, err := os.ReadFile(fields)
	if r.code != 0 || err != nil || string(got) != "pr=a_b_c\nempty=-\n" {
		t.Errorf("--field: code %d, fields file %q (%v); want 0, %q", r.code, got, err, "pr=a_b_c\nempty=-\n")
	}
}

// If a name with no entry runs anything, or says more than one line, this goes red.
func TestUnknownNameExits2(t *testing.T) {
	r := runFixture(t, handoff("", ""), "", "no-such-command", "x")
	want := "swarm: the binary has no command 'no-such-command'\n"
	if r.code != 2 || r.stdout != "" || r.stderr != want {
		t.Errorf("an unknown name: code %d, stdout %q, stderr %q; want 2, nothing, %q", r.code, r.stdout, r.stderr, want)
	}
}

// markerMismatch lists each entry of table, fixtures aside, with no marker file in dir, and each
// marker with no entry. A missing dir has no markers.
func markerMismatch(table map[string]entry, dir string) ([]string, error) {
	des, err := os.ReadDir(dir)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	markers := map[string]bool{}
	for _, de := range des {
		markers[de.Name()] = true
	}
	var bad []string
	for name, e := range table {
		if !e.fixture && !markers[name] {
			bad = append(bad, "the entry "+name+" has no marker "+filepath.Join(dir, name))
		}
	}
	for name := range markers {
		if _, ok := table[name]; !ok {
			bad = append(bad, "the marker "+filepath.Join(dir, name)+" names no entry of the table")
		}
	}
	slices.Sort(bad)
	return bad, nil
}

// If the table and bin/ported/ name different entries, bin/swarm.sh sends a name to a binary that
// lacks it, or keeps a ported one in bash: this goes red.
func TestTableMatchesMarkers(t *testing.T) {
	bad, err := markerMismatch(entries, portedDir)
	if err != nil || len(bad) != 0 {
		t.Errorf("the table and %s differ (%v):\n%s", portedDir, err, strings.Join(bad, "\n"))
	}
}

// If register stops refusing a name the table already holds, a second file that claims a name silently
// replaces the first file's entry: this goes red. It registers into a copy of the real table, so the
// real one stays as the inits left it.
func TestRegisterPanicsOnAHeldName(t *testing.T) {
	saved := entries
	entries = maps.Clone(saved)
	t.Cleanup(func() { entries = saved })
	const held = "_require-trusted"
	if _, ok := entries[held]; !ok {
		t.Fatalf("the table does not hold %s, so this test checks nothing", held)
	}
	defer func() {
		got, _ := recover().(string)
		if want := "swarm: two entries register the name " + held; got != want {
			t.Errorf("register of a held name panicked with %q, want %q", got, want)
		}
	}()
	register(held, entry{run: func(*call) int { return 0 }})
	t.Errorf("register of the held name %s returned, want a panic", held)
}

// If the check stops catching an entry with no marker or a marker with no entry, or counts a fixture
// or a missing directory against the table, this goes red.
func TestMarkerCheckCatchesEachSide(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "marked"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	noop := func(*call) int { return 0 }
	cases := []struct {
		name  string
		table map[string]entry
		dir   string
		want  []string
	}{
		{"matched", map[string]entry{"marked": {run: noop}, "fix": {fixture: true, run: noop}}, dir, nil},
		{"entry with no marker", map[string]entry{"marked": {run: noop}, "new": {run: noop}}, dir,
			[]string{"the entry new has no marker " + filepath.Join(dir, "new")}},
		{"marker with no entry", map[string]entry{}, dir,
			[]string{"the marker " + filepath.Join(dir, "marked") + " names no entry of the table"}},
		{"missing dir", map[string]entry{"fix": {fixture: true, run: noop}}, filepath.Join(dir, "none"), nil},
	}
	for _, tc := range cases {
		bad, err := markerMismatch(tc.table, tc.dir)
		if err != nil || !slices.Equal(bad, tc.want) {
			t.Errorf("%s: markerMismatch = %q (%v), want %q", tc.name, bad, err, tc.want)
		}
	}
}
