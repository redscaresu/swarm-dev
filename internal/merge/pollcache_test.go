package merge

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
)

// The forms and sums python3's json.dumps([argv, filt]) and its sha256 gave, run by hand through
// bin/lib/poll_cache.py's own imports (Python 3.9.6 and 3.14.7, 2026-11-25, the same on both); the
// PR that added them has the run. The second argv ends in the byte 0xff, which Python's argv holds
// as U+DCFF through surrogateescape.
var pollKeyRows = []struct {
	name      string
	argv      []string
	filt      string
	form, sum string
}{
	{
		name: "pages' argv, its path holding & and ? and non-ASCII",
		argv: []string{"api", "--paginate", "repos/o/r/commits/brånch-\U0001F600/check-runs?per_page=100&filter=latest"},
		form: `[["api", "--paginate", "repos/o/r/commits/br\u00e5nch-\ud83d\ude00/check-runs?per_page=100&filter=latest"], ""]`,
		sum:  "246ac6eea1be394f0f42c5266828fa746765e8ba0c50e9a3bfcf7a7d89fe0812",
	},
	{
		name: "the command form's argv, with a byte that is not UTF-8",
		argv: []string{"gh", "api", "repos/o/r/pulls?state=open&per_page=100", "-q", ".[].number", "café\xff"},
		form: `[["gh", "api", "repos/o/r/pulls?state=open&per_page=100", "-q", ".[].number", "caf\u00e9\udcff"], ""]`,
		sum:  "f97d77fa989d727acd3dae7708438f13782a79bfbb39a97ed1bc51a477aeadc1",
	},
	{
		name: "a filter",
		argv: []string{"api", "--paginate", "repos/o/r/commits/abc/check-runs?per_page=100"},
		filt: ".check_runs[] | .name",
		form: `[["api", "--paginate", "repos/o/r/commits/abc/check-runs?per_page=100"], ".check_runs[] | .name"]`,
		sum:  "56a7462a64a214c99823138a7c49b9475a56deaf612ec79dcbb6f0fbd1a37961",
	},
}

// pollAt is the read time of the entry Python's put wrote, pollPutOut the output it kept, and
// pollPutBytes the file, from poll_cache.put(path, form, out, 1764000000.123456) for the first row's
// form, run by hand as pollKeyRows were.
const (
	pollAt       = 1764000000.123456
	pollPutOut   = "{\"total_count\": 1, \"check_runs\": [{\"name\": \"tëst \\\"q\\\"\", \"x\": \"\U0001F600\"}]}\n"
	pollPutBytes = `{"form": [["api", "--paginate", "repos/o/r/commits/br\u00e5nch-\ud83d\ude00/check-runs?per_page=100&filter=latest"], ""], "at": 1764000000.123456, "out": "{\"total_count\": 1, \"check_runs\": [{\"name\": \"t\u00ebst \\\"q\\\"\", \"x\": \"\ud83d\ude00\"}]}\n"}`
)

// testCache is a poll cache in a fresh folder, through the real store, its clock stopped at now and
// its age file in the folder above.
func testCache(t *testing.T, now time.Time) *pollCache {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, "poll-cache")
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	return &pollCache{st: store.Files{}, dir: dir, now: func() time.Time { return now }, ageFile: filepath.Join(root, "age")}
}

// at is the instant secs epoch seconds name, to the nanosecond.
func at(secs float64) time.Time {
	return time.Unix(0, int64(secs*float64(time.Second)))
}

// ageNote returns what the cache's age file holds, "" when it is missing.
func ageNote(t *testing.T, c *pollCache) string {
	t.Helper()
	b, err := os.ReadFile(c.ageFile)
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	return string(b)
}

// names returns the names in dir, sorted.
func names(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, e := range entries {
		got = append(got, e.Name())
	}
	return got
}

// If pollForm wrote the form other than json.dumps does (é or the emoji raw, no space after a comma,
// the byte 0xff kept raw), or the key hashed other text, a Go reader and a Python one would never
// share an entry: this goes red.
func TestPollKeyMatchesPython(t *testing.T) {
	for _, r := range pollKeyRows {
		form := pollForm(r.argv, r.filt)
		if form != r.form {
			t.Errorf("%s: pollForm = %s\nwant          %s", r.name, form, r.form)
		}
		if got := pollKey(form); got != r.sum {
			t.Errorf("%s: pollKey = %s, want %s", r.name, got, r.sum)
		}
	}
	form := pollForm(pollKeyRows[0].argv, "")
	for dir, want := range map[string]string{"/p/.swarm/poll-cache": "/p/.swarm/poll-cache/", "/p/c/": "/p/c/"} {
		c := &pollCache{dir: dir}
		if got := c.path(form, pollEntry); got != want+pollKeyRows[0].sum+".json" {
			t.Errorf("path in %s = %s, want %s", dir, got, want+pollKeyRows[0].sum+".json")
		}
	}
}

// If put wrote its entry other than json.dump does (another key order, separators or float) or under
// another name, Python's entry would not take it; if entry misread Python's file, the Go would read gh
// again: this goes red. Each side's file is the other's, byte for byte.
func TestPollEntryRoundTripsWithPython(t *testing.T) {
	form := pollForm(pollKeyRows[0].argv, "")
	c := testCache(t, at(pollAt+5.75))
	c.put(form, pollPutOut, pollAt)
	path := c.path(form, pollEntry)
	if got, err := os.ReadFile(path); err != nil || string(got) != pollPutBytes {
		t.Errorf("put wrote %s, %v\nwant Python's %s", got, err, pollPutBytes)
	}
	if got := names(t, c.dir); !slices.Equal(got, []string{pollKeyRows[0].sum + ".json"}) {
		t.Errorf("%s holds %q after put; want only the entry", c.dir, got)
	}

	c = testCache(t, at(pollAt+5.75))
	if err := os.WriteFile(c.path(form, pollEntry), []byte(pollPutBytes), 0o600); err != nil {
		t.Fatal(err)
	}
	if out, ok := c.entry(form, 10); !ok || out != pollPutOut {
		t.Errorf("entry of Python's file = %q, %v; want %q, true", out, ok, pollPutOut)
	}
	if got := ageNote(t, c); got != "5\n" {
		t.Errorf("the age file holds %q after taking a 5.75 s old entry; want %q", got, "5\n")
	}
}

// If entry took an entry of another form, of another shape or past its max age, a reader would hand
// its caller another read's output or one older than it asked for; if it refused a shape Python
// takes, the Go would read gh where Python reads the entry: this goes red. Each file but at's sits in
// the first row's form's entry, read 5.75 s after pollAt with a max age of 10.
func TestPollEntryTakesOnlyItsFormUnderItsAge(t *testing.T) {
	form := pollForm(pollKeyRows[0].argv, "")
	other := pollForm(pollKeyRows[0].argv, ".x")
	entryOf := func(form, at, out string) string {
		return `{"form": ` + form + `, "at": ` + at + `, "out": ` + out + `}`
	}
	type row struct {
		name, file string
		maxAge     int
		want       bool
	}
	check := func(r row, now time.Time) {
		t.Helper()
		c := testCache(t, now)
		if err := os.WriteFile(c.path(form, pollEntry), []byte(r.file), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, ok := c.entry(form, r.maxAge); ok != r.want {
			t.Errorf("%s: entry = %v, want %v", r.name, ok, r.want)
		}
		if note := ageNote(t, c); (note != "") != r.want {
			t.Errorf("%s: the age file holds %q; want a line only when the entry is taken", r.name, note)
		}
	}
	for _, r := range []row{
		{"Python's put", pollPutBytes, 10, true},
		{"just under the max age", pollPutBytes, 6, true},
		{"older than the max age", pollPutBytes, 5, false},
		{"another form's entry under this key", entryOf(other, "1764000000.123456", `"x"`), 10, false},
		{"the form with another argv", entryOf(pollForm(pollKeyRows[2].argv, ""), "1764000000.123456", `"x"`), 10, false},
		{"the form's argv as one string", entryOf(`["api --paginate", ""]`, "1764000000.123456", `"x"`), 10, false},
		{"no form", `{"at": 1764000000.123456, "out": "x"}`, 10, false},
		{"from the future", entryOf(form, "1764000006", `"x"`), 10, false},
		{"at as a whole number", entryOf(form, "1764000000", `"x"`), 10, true},
		{"at as a string", entryOf(form, `"1764000000"`, `"x"`), 10, false},
		{"at true, which Python's isinstance takes as the int 1", entryOf(form, "true", `"x"`), 1764000010, true},
		{"at an int too large for a float", entryOf(form, "1"+strings.Repeat("0", 400), `"x"`), 10, false},
		{"at NaN", entryOf(form, "NaN", `"x"`), 10, false},
		{"out a number", entryOf(form, "1764000000.123456", "1"), 10, false},
		{"out null", entryOf(form, "1764000000.123456", "null"), 10, false},
		{"a list", "[" + pollPutBytes + "]", 10, false},
		{"cut off", pollPutBytes[:len(pollPutBytes)-1], 10, false},
		{"a UTF-8 BOM first", "\xef\xbb\xbf" + pollPutBytes, 10, false},
		{"form given twice, the last wrong", `{"form": ` + form + `, "form": ` + other + `, "at": 1764000000.1, "out": "x"}`, 10, false},
		{"form given twice, the last right", `{"form": ` + other + `, "form": ` + form + `, "at": 1764000000.1, "out": "x"}`, 10, true},
	} {
		check(r, at(pollAt+5.75))
	}
	// At the edges, read on whole seconds so the age is exact: Python takes 0 <= age < max age.
	check(row{"exactly the max age old", entryOf(form, "1764000000", `"x"`), 6, false}, time.Unix(1764000006, 0))
	check(row{"written at this instant", entryOf(form, "1764000000", `"x"`), 1, true}, time.Unix(1764000000, 0))
	c := testCache(t, at(pollAt+5.75))
	if out, ok := c.entry(form, 10); ok {
		t.Errorf("entry with no file = %q, true; want false", out)
	}
}

// If prune deleted a file 600 s old or younger, a reader would lose an entry it may still take; if it
// skipped a dot name, a lock or a temp file, the folder would fill with what killed readers left; if
// it deleted a folder, or judged a symlink by its own time where os.stat follows it: this goes red.
func TestPollPruneRemovesOnlyFilesOlderThan600s(t *testing.T) {
	now := at(pollAt)
	c := testCache(t, now)
	target := filepath.Join(filepath.Dir(c.dir), "old-target")
	ages := map[string]time.Duration{
		"old.json":    pollPrune + time.Millisecond,
		"old.lock":    time.Hour,
		"tmpab12.tmp": time.Hour,
		".old":        time.Hour,
		"600s.json":   pollPrune,
		"599s.json":   pollPrune - time.Second,
		"old-folder":  time.Hour,
	}
	for name := range ages {
		p := filepath.Join(c.dir, name)
		mk := func() error { return os.WriteFile(p, []byte("x"), 0o600) }
		if name == "old-folder" {
			mk = func() error { return os.Mkdir(p, 0o700) }
		}
		if err := mk(); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(p, now.Add(-ages[name]), now.Add(-ages[name])); err != nil {
			t.Fatal(err)
		}
	}
	// A new link to a file an hour old, outside the folder: os.stat follows it, so it goes, and the
	// file it names stays.
	if err := os.WriteFile(target, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(target, now.Add(-time.Hour), now.Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(c.dir, "link.json")); err != nil {
		t.Fatal(err)
	}
	c.prune()
	want := []string{"599s.json", "600s.json", "old-folder"}
	if got := names(t, c.dir); !slices.Equal(got, want) {
		t.Errorf("%s holds %q after prune; want %q", c.dir, got, want)
	}
	if _, err := os.Stat(target); err != nil {
		t.Errorf("prune reached %s, outside the folder, through a link: %v", target, err)
	}
}

// If took wrote the newest age in place of the oldest, or rounded it up, wait-pr would pause too long
// before its next poll: this goes red.
func TestPollTookWritesTheOldestAgeInWholeSeconds(t *testing.T) {
	c := testCache(t, at(pollAt))
	for _, r := range []struct {
		secs float64
		want string
	}{{0.4, "0\n"}, {3.9, "3\n"}, {7.2, "7\n"}, {5, "7\n"}} {
		c.took(r.secs)
		if got := ageNote(t, c); got != r.want {
			t.Errorf("after took(%v), the age file holds %q; want %q", r.secs, got, r.want)
		}
	}
}

// If newPollCache took its clock from SWARM_DASH_NOW, a pinned run would judge every entry by the pin
// in place of real time, as time.time() does not; if it did not read SWARM_POLL_CACHE_AGE, wait-pr
// would never learn the age it took: this goes red.
func TestNewPollCacheTakesTheAgeFileAndTheRealClock(t *testing.T) {
	t.Setenv(pollAgeVar, "/w/age")
	t.Setenv("SWARM_DASH_NOW", "1")
	before := time.Now()
	c := newPollCache(store.Files{}, "/w/poll-cache")
	got := c.now()
	if c.ageFile != "/w/age" || c.dir != "/w/poll-cache" {
		t.Errorf("newPollCache: ageFile %q, dir %q; want /w/age, /w/poll-cache", c.ageFile, c.dir)
	}
	if got.Before(before) || got.After(time.Now()) {
		t.Errorf("newPollCache's clock read %v, not the real time", got)
	}
}
