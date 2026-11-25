package main

import (
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"testing"
)

// resendDir writes a project's resend files in a new folder: events.tsv, the resent file and the
// briefs folder with the markers given by file name. It returns the six arguments _resend-rows takes.
func resendDir(t *testing.T, events, resent string, markers map[string]string) []string {
	t.Helper()
	dir := t.TempDir()
	briefs := filepath.Join(dir, "briefs")
	write := func(path, text string) {
		if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Mkdir(briefs, 0o700); err != nil {
		t.Fatal(err)
	}
	write(filepath.Join(dir, "events.tsv"), events)
	write(filepath.Join(dir, "resend"), resent)
	for n, text := range markers {
		write(filepath.Join(briefs, n), text)
	}
	return []string{filepath.Join(dir, "events.tsv"), filepath.Join(dir, "resend"), briefs, "w1:p1 w1:p2", "conduct-backlog-x", "32"}
}

// left lists the files the briefs folder still holds.
func left(t *testing.T, briefs string) []string {
	t.Helper()
	es, err := os.ReadDir(briefs)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, e := range es {
		out = append(out, e.Name())
	}
	return out
}

const resendList = `{"result": {"agents": [{"name": "alpha", "pane_id": "w1:p1", "agent_status": "idle"}, ` +
	`{"name": "beta", "pane_id": "w1:p2", "agent_status": "working"}]}}`

// If the entry stops handing its arguments to the rule in their order (events, resent, briefs, panes,
// backlog, name max), stops reading stdin as the list, or stops removing the markers the rule names
// through the store, the rows or the briefs folder change and this goes red. Each row is what the
// inline Python printed on the same files.
func TestResendRowsPrintsAndRemoves(t *testing.T) {
	args := resendDir(t, "T1\tstory\talpha\tw1:p0\tok\nT1\tconduct\t--backlog\tw1:p0\tok\n",
		"alpha\tT0\tstory\t1\n", map[string]string{
			"alpha.unsent": "alpha w1:p1 builder\npid 1\n", "beta.unsent": "beta w1:p2 builder\npid 1\n", ".x.unsent": "beta w1:p2\n"})
	got := runFixture(t, handoff("", ""), resendList, append([]string{"_resend-rows"}, args...)...)
	want := "w1:p1\talpha\tT1\tstory\t1\talpha\tbuilder\tnew\talpha\n"
	if got.code != 0 || got.stdout != want || got.stderr != "" || len(got.writes) != 0 {
		t.Errorf("_resend-rows: code %d, stdout %q, stderr %q, writes %v; want 0, %q, nothing else", got.code, got.stdout, got.stderr, got.writes, want)
	}
	if l := left(t, args[2]); !slices.Equal(l, []string{".x.unsent", "alpha.unsent"}) {
		t.Errorf("_resend-rows left %q in the briefs folder, want .x.unsent and alpha.unsent", l)
	}
}

// If a failure of the program as a whole (here a marker that is not UTF-8) stops exiting 1 with no row,
// or loses the removal of the marker read before it, the caller's `|| return 0` no longer holds and
// this goes red.
func TestResendRowsFailsAsAWhole(t *testing.T) {
	args := resendDir(t, "T1\tstory\talpha\tw1:p0\tok\n", "", map[string]string{
		"a.unsent": "ghost w1:p1\n", "b.unsent": "alpha w1:p1 \xff\n"})
	got := runFixture(t, handoff("", ""), resendList, append([]string{"_resend-rows"}, args...)...)
	want := "swarm: _resend-rows: resend: not UTF-8: " + filepath.Join(args[2], "b.unsent") + "\n"
	if got.code != 1 || got.stdout != "" || got.stderr != want {
		t.Errorf("a marker that is not UTF-8: code %d, stdout %q, stderr %q; want 1, nothing, %q", got.code, got.stdout, got.stderr, want)
	}
	if l := left(t, args[2]); !slices.Equal(l, []string{"b.unsent"}) {
		t.Errorf("a marker that is not UTF-8: left %q, want only b.unsent", l)
	}
	got = runFixture(t, handoff("", ""), "herdr: no server", append([]string{"_resend-rows"}, args...)...)
	if got.code != 1 || got.stdout != "" {
		t.Errorf("a list that is not JSON: code %d, stdout %q; want 1 and no row", got.code, got.stdout)
	}
}

// If the entry runs with a wrong number of arguments, or a name max that is not a whole number, it must
// stop in one line with exitUsage rather than guess: dropping either check goes red.
func TestResendRowsUsage(t *testing.T) {
	args := resendDir(t, "", "", nil)
	for _, c := range []struct {
		args []string
		line string
	}{
		{args[:5], "_resend-rows takes <events> <resent> <briefs> <panes> <backlog> <name-max>, and was given 5 argument(s)"},
		{append(slices.Clone(args), "x"), "_resend-rows takes <events> <resent> <briefs> <panes> <backlog> <name-max>, and was given 7 argument(s)"},
		{append(slices.Clone(args[:5]), "-1"), "_resend-rows: <name-max> takes a whole number, not '-1'"},
		{append(slices.Clone(args[:5]), "3x"), "_resend-rows: <name-max> takes a whole number, not '3x'"},
	} {
		got := runFixture(t, handoff("", ""), resendList, append([]string{"_resend-rows"}, c.args...)...)
		if got.code != exitUsage || got.stdout != "" || got.stderr != "swarm: "+c.line+"\n" {
			t.Errorf("_resend-rows with %s argument(s): code %d, stdout %q, stderr %q; want %d, nothing, %q",
				strconv.Itoa(len(c.args)), got.code, got.stdout, got.stderr, exitUsage, "swarm: "+c.line+"\n")
		}
	}
}
