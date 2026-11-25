package merge

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/redscaresu/swarm-dev/internal/clock"
	"github.com/redscaresu/swarm-dev/internal/iface"
)

// The poll cache's entries, as bin/lib/poll_cache.py keeps them in one folder
// (<project>/.swarm/poll-cache): one JSON file per read's form, named by the form's key, holding the
// form, when its read started and gh's output. Nothing runs this Go yet; poll_cache.py still reads
// and writes the folder.

const (
	// pollPrune is poll_cache.py's PRUNE_SECONDS: writing an entry deletes any file in the folder
	// older than this.
	pollPrune = 600 * time.Second
	// pollAgeVar names the file a reader that took an entry writes its age to. wait-pr empties that
	// file before each poll, then pauses that much less.
	pollAgeVar = "SWARM_POLL_CACHE_AGE"
	// pollEntry ends an entry's name, after its key. put's temp file ends in .tmp instead, so no
	// reader takes half of one.
	pollEntry = ".json"
)

// pollCache is one process's poll cache: the folder, and the oldest age it took, which
// poll_cache.py keeps as its module's oldest.
type pollCache struct {
	st  iface.Store
	dir string
	// now is the real clock, as Python's time.time() is: an entry's age runs on real time, even
	// under a test's pin.
	now func() time.Time
	// ageFile is the file pollAgeVar names, "" for none.
	ageFile string
	// oldest is the age in whole seconds of the oldest entry taken, 0 until one is.
	oldest int
}

// newPollCache is the poll cache in dir, through st, with its age file from the environment.
func newPollCache(st iface.Store, dir string) *pollCache {
	return &pollCache{st: st, dir: dir, now: clock.Real, ageFile: os.Getenv(pollAgeVar)}
}

// pollForm is the text json.dumps gives a read's form, [argv, filt]: gh's argv and its output
// filter, "" for none. Its sha256 is the form's key, and an entry is taken only for the same text.
func pollForm(argv []string, filt string) string {
	return Dumps([]any{argv, filt})
}

// pollKey is form's key: the sha256 of its text, in hex, as poll_cache.py's through names it.
func pollKey(form string) string {
	sum := sha256.Sum256([]byte(form))
	return hex.EncodeToString(sum[:])
}

// path is os.path.join(dir, key + ext) for form's key: its entry with ext pollEntry.
func (c *pollCache) path(form, ext string) string {
	sep := string(filepath.Separator)
	name := pollKey(form) + ext
	if strings.HasSuffix(c.dir, sep) {
		return c.dir + name
	}
	return c.dir + sep + name
}

// entry returns the output form's entry keeps, as poll_cache.py's entry does, when the entry was
// written under maxAge seconds ago: a file that reads as JSON, holding an object whose "form" is
// form, whose "out" is a string and whose "at" is a number of epoch seconds. A bool counts as a
// number, as Python's isinstance takes it for an int. It notes the entry's age through took. A file
// that does not read or is not JSON, an entry of another form or shape, and one from the future or
// maxAge or more old all give false. So does an "at" too large for a float, where Python's
// subtraction raises OverflowError. The output is as Loads gives it, a lone surrogate in its three
// bytes: a caller that wants back the bytes surrogateescape kept turns U+DC80 to U+DCFF into a byte.
func (c *pollCache) entry(form string, maxAge int) (string, bool) {
	data, err := c.st.ReadFile(c.path(form, pollEntry))
	if err != nil {
		return "", false
	}
	v, err := Loads(string(data))
	if err != nil {
		return "", false
	}
	d, ok := v.(*Object)
	if !ok {
		return "", false
	}
	got, ok := d.Get("form")
	if !ok || Dumps(got) != form {
		return "", false
	}
	outV, _ := d.Get("out")
	out, ok := outV.(string)
	if !ok {
		return "", false
	}
	atV, _ := d.Get("at")
	at, ok := seconds(atV)
	if !ok {
		return "", false
	}
	age := epochSeconds(c.now()) - at
	if !(0 <= age && age < float64(maxAge)) {
		return "", false
	}
	c.took(age)
	return out, true
}

// seconds returns v as a float, when Python's isinstance(v, (int, float)) is true of it.
func seconds(v any) (float64, bool) {
	switch v := v.(type) {
	case bool:
		if v {
			return 1, true
		}
		return 0, true
	case Int:
		// An Int is digits, so ParseFloat's one error is ErrRange, with ±Inf, which no age check passes.
		f, _ := strconv.ParseFloat(string(v), 64)
		return f, true
	case float64:
		return v, true
	}
	return 0, false
}

// epochSeconds is t as Python's time.time() gives it: its nanoseconds since the epoch over 1e9.
func epochSeconds(t time.Time) float64 {
	return float64(t.UnixNano()) / float64(time.Second)
}

// took notes an entry secs old taken in place of a read, as poll_cache.py's took does: the oldest
// such age in whole seconds goes to the age file, if any, as one line, best effort.
func (c *pollCache) took(secs float64) {
	c.oldest = max(c.oldest, int(secs))
	if c.ageFile != "" {
		_ = c.st.WriteLine(c.ageFile, strconv.Itoa(c.oldest))
	}
}

// put keeps out for form as read at at (epoch seconds), as poll_cache.py's put does: the entry as
// json.dump writes {"form": form, "at": at, "out": out}, through a temp file renamed over the old
// one, so no reader sees half of one. Then it prunes the folder. A write that fails costs only a
// later read, so put drops its error.
func (c *pollCache) put(form, out string, at float64) {
	entry := `{"form": ` + form + `, "at": ` + Dumps(at) + `, "out": ` + Dumps(out) + `}`
	_ = c.st.WriteAtomic(c.path(form, pollEntry), []byte(entry))
	c.prune()
}

// prune deletes each file in the folder older than pollPrune, as poll_cache.py's prune does: entries
// no reader takes, and locks and temp files a killed reader left. Python's os.listdir lists dot
// names too, which a * level skips, so it lists .* as well. A file whose stat or delete fails, a
// folder among them, is left.
func (c *pollCache) prune() {
	cut := c.now().Add(-pollPrune)
	for _, pattern := range []string{"*", ".*"} {
		paths, _ := c.st.Glob(c.dir, pattern)
		for _, p := range paths {
			if info, err := c.st.Stat(p); err == nil && info.ModTime().Before(cut) {
				c.remove(p)
			}
		}
	}
}

// remove deletes the file at path, as poll_cache.py's remove does, best effort.
func (c *pollCache) remove(path string) {
	_ = c.st.Remove(path)
}
