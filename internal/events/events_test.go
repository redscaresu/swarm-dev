package events

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
)

// stamp is the time every test appends at, in a zone an hour east of UTC, so a line that kept the
// zone shows 11:04:05 where UTC is 10:04:05.
var stamp = time.Date(2026, 11, 24, 11, 4, 5, 0, time.FixedZone("east", 3600))

// stampCol is stamp's first column.
const stampCol = "2026-11-24T10:04:05Z"

// testVersion is the version the default plugin.json holds.
const testVersion = "0.32.0"

// project is a temp project and plugin root, with the environment the Appender reads pinned: no
// forbidden project and the pane %7, unless a test changes them.
func project(t *testing.T, manifestJSON string) (dir, root string) {
	t.Helper()
	t.Setenv(forbidVar, "")
	t.Setenv(paneVar, "%7")
	dir, root = t.TempDir(), t.TempDir()
	writeManifest(t, root, manifestJSON)
	return dir, root
}

// writeManifest writes root's plugin.json.
func writeManifest(t *testing.T, root, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(root, ".claude-plugin"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(root+manifest, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

// logOf is the project's events.tsv.
func logOf(t *testing.T, dir string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(dir, LogFile))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// TestLines writes one line per case to a fresh project and compares the whole file.
func TestLines(t *testing.T) {
	tail := Sep + "version=" + testVersion
	cases := []struct {
		name, target, outcome string
		fields                []string
		unsetPane             bool
		want                  string
	}{
		{name: "Sep twice in the outcome", target: "s", outcome: "a ~~ b ~~ c",
			want: "s\t%7\ta b c" + tail},
		{name: "outcome ending in the cut", target: "s", outcome: "done ~~",
			want: "s\t%7\tdone" + tail},
		{name: "outcome ending in the cut after spaces and a Sep", target: "s", outcome: "x ~~  ~~",
			want: "s\t%7\tx" + tail},
		{name: "a tab in the target", target: "a\tb", outcome: "ok",
			want: "a b\t%7\tok" + tail},
		{name: "an empty target and outcome", target: "", outcome: "",
			want: "-\t%7\tok" + tail},
		{name: "an unset pane", target: "s", outcome: "ok", unsetPane: true,
			want: "s\t-\tok" + tail},
		{name: "breaks in the outcome", target: "s", outcome: "a\nb\rc\td",
			want: "s\t%7\ta b c d" + tail},
		{name: "good fields before version=", target: "s", outcome: "ok", fields: []string{"slug=x", "a_b=c=d"},
			want: "s\t%7\tok" + Sep + "slug=x a_b=c=d version=" + testVersion},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir, root := project(t, `{"version": "`+testVersion+`"}`)
			if c.unsetPane {
				if err := os.Unsetenv(paneVar); err != nil {
					t.Fatal(err)
				}
			}
			var stderr bytes.Buffer
			if err := New(store.Files{}, dir, root, &stderr).Append(stamp, "cmd", c.target, c.outcome, c.fields...); err != nil {
				t.Fatal(err)
			}
			if got, want := logOf(t, dir), stampCol+"\tcmd\t"+c.want+"\n"; got != want {
				t.Errorf("line\n got %q\nwant %q", got, want)
			}
			if stderr.Len() != 0 {
				t.Errorf("stderr %q, want nothing", stderr.String())
			}
		})
	}
}

// TestBadField leaves out a bad field with its warning, cut at its first tab, and still writes the
// line with the good ones.
func TestBadField(t *testing.T) {
	dir, root := project(t, `{"version": "`+testVersion+`"}`)
	var stderr bytes.Buffer
	if err := New(store.Files{}, dir, root, &stderr).Append(stamp, "cmd", "s", "ok", "Bad=x", "k=a\tb", "slug=y"); err != nil {
		t.Fatal(err)
	}
	if got, want := logOf(t, dir), stampCol+"\tcmd\ts\t%7\tok"+Sep+"slug=y version="+testVersion+"\n"; got != want {
		t.Errorf("line\n got %q\nwant %q", got, want)
	}
	want := "append_event: left out Bad=x: a field is key=value, the key [a-z_]+, the value not empty and with no whitespace\n" +
		"append_event: left out k=a: a field is key=value, the key [a-z_]+, the value not empty and with no whitespace\n"
	if stderr.String() != want {
		t.Errorf("stderr\n got %q\nwant %q", stderr.String(), want)
	}
}

// TestVersionReadOnce keeps the first version when plugin.json changes between two appends.
func TestVersionReadOnce(t *testing.T) {
	dir, root := project(t, `{"version": "1.0"}`)
	a := New(store.Files{}, dir, root, &bytes.Buffer{})
	if err := a.Append(stamp, "one", "s", "ok"); err != nil {
		t.Fatal(err)
	}
	writeManifest(t, root, `{"version": "2.0"}`)
	if err := a.Append(stamp, "two", "s", "ok"); err != nil {
		t.Fatal(err)
	}
	want := stampCol + "\tone\ts\t%7\tok" + Sep + "version=1.0\n" + stampCol + "\ttwo\ts\t%7\tok" + Sep + "version=1.0\n"
	if got := logOf(t, dir); got != want {
		t.Errorf("log\n got %q\nwant %q", got, want)
	}
}

// TestVersionText keeps a version that ends in LFs, which $( ) strips, and drops one that ends in a
// CR or holds an LF inside, or that plugin.json does not hold.
func TestVersionText(t *testing.T) {
	cases := []struct{ name, json, want string }{
		{"1.0 then an LF", `{"version": "1.0\n"}`, "ok" + Sep + "version=1.0"},
		{"1.0 then two LFs", `{"version": "1.0\n\n"}`, "ok" + Sep + "version=1.0"},
		{"1.0 then a CR", `{"version": "1.0\r"}`, "ok"},
		{"1. then an LF then 0", `{"version": "1.\n0"}`, "ok"},
		{"only LFs", `{"version": "\n"}`, "ok"},
		{"no version", `{}`, "ok"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir, root := project(t, c.json)
			if err := New(store.Files{}, dir, root, &bytes.Buffer{}).Append(stamp, "cmd", "s", ""); err != nil {
				t.Fatal(err)
			}
			if got, want := logOf(t, dir), stampCol+"\tcmd\ts\t%7\t"+c.want+"\n"; got != want {
				t.Errorf("line\n got %q\nwant %q", got, want)
			}
		})
	}
}

// failingStore is the real store, but its AppendLine fails with errAppend.
type failingStore struct{ store.Files }

var errAppend = errors.New("append failed")

func (failingStore) AppendLine(string, string) error { return errAppend }

// TestAppendFails returns AppendLine's error and writes nothing on stderr.
func TestAppendFails(t *testing.T) {
	dir, root := project(t, `{"version": "`+testVersion+`"}`)
	var stderr bytes.Buffer
	err := New(failingStore{}, dir, root, &stderr).Append(stamp, "cmd", "s", "ok", "slug=x")
	if !errors.Is(err, errAppend) {
		t.Errorf("err %v, want %v", err, errAppend)
	}
	if stderr.Len() != 0 {
		t.Errorf("stderr %q, want nothing", stderr.String())
	}
}

// TestForbidden refuses the project forbidVar names through a symlink, making no .swarm, and writes
// when it names another folder.
func TestForbidden(t *testing.T) {
	dir, root := project(t, `{"version": "`+testVersion+`"}`)
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(dir, link); err != nil {
		t.Fatal(err)
	}
	t.Setenv(forbidVar, link)
	err := New(store.Files{}, dir, root, &bytes.Buffer{}).Append(stamp, "cmd", "s", "ok")
	if err == nil || !strings.Contains(err.Error(), forbidVar) {
		t.Errorf("err %v, want one naming %s", err, forbidVar)
	}
	if _, serr := os.Lstat(filepath.Join(dir, ".swarm")); !errors.Is(serr, os.ErrNotExist) {
		t.Errorf("a refused append left .swarm: %v", serr)
	}

	t.Setenv(forbidVar, t.TempDir())
	if err := New(store.Files{}, dir, root, &bytes.Buffer{}).Append(stamp, "cmd", "s", "ok"); err != nil {
		t.Fatal(err)
	}
	if got, want := logOf(t, dir), stampCol+"\tcmd\ts\t%7\tok"+Sep+"version="+testVersion+"\n"; got != want {
		t.Errorf("line\n got %q\nwant %q", got, want)
	}
}
