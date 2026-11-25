package merge

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
)

// lockPid is the pid the cache under test writes in a lock it takes; holderPid is another reader's.
// pyLockPause is poll_cache.py's LOCK_PAUSE, 0.05 s, written out so a change to pollLockPause fails.
const (
	lockPid     = 31337
	holderPid   = 4242
	pyLockPause = 50 * time.Millisecond
)

// lockStore is the real store with three seams: which pids run, a failing create or mkdir, and a
// hook that runs before each create, for another reader that acts between two looks.
type lockStore struct {
	store.Files
	alive        map[int]bool
	createErr    error
	mkdirErr     error
	beforeCreate func()
}

func (s *lockStore) Alive(pid int) bool { return s.alive[pid] }

func (s *lockStore) CreateExclusive(path string, data []byte) error {
	if s.beforeCreate != nil {
		s.beforeCreate()
	}
	if s.createErr != nil {
		return s.createErr
	}
	return s.Files.CreateExclusive(path, data)
}

func (s *lockStore) MkdirAll(path string) error {
	if s.mkdirErr != nil {
		return s.mkdirErr
	}
	return s.Files.MkdirAll(path)
}

// lockClock is a stopped clock that each pause moves on, recording the pause, then running onPause
// with the count of pauses so far.
type lockClock struct {
	t       time.Time
	pauses  []time.Duration
	onPause func(n int)
}

func (k *lockClock) now() time.Time { return k.t }

func (k *lockClock) pause(d time.Duration) {
	k.t = k.t.Add(d)
	k.pauses = append(k.pauses, d)
	if k.onPause != nil {
		k.onPause(len(k.pauses))
	}
}

// lockRig is a cache on: a fresh folder through a lockStore, a lockClock at a whole second, so
// sums of pauses land on exact float seconds, and a max age of 10 s.
type lockRig struct {
	t       *testing.T
	on      pollOn
	st      *lockStore
	clk     *lockClock
	form    string
	lk      string
	fetches int
}

func newLockRig(t *testing.T) *lockRig {
	t.Helper()
	st := &lockStore{alive: map[int]bool{holderPid: true}}
	clk := &lockClock{t: time.Unix(1764000000, 0)}
	dir := filepath.Join(t.TempDir(), "poll-cache")
	c := &pollCache{st: st, dir: dir, now: clk.now}
	r := &lockRig{t: t, on: pollOn{c: c, maxAge: 10, pause: clk.pause, pid: lockPid}, st: st, clk: clk}
	r.form = pollForm(pollKeyRows[0].argv, "")
	r.lk = c.path(r.form, pollLock)
	return r
}

// read is the rig's read: each fetch is counted, and returns "fresh" after running during, if set.
func (r *lockRig) read(during func()) pollRead {
	return pollRead{argv: pollKeyRows[0].argv, fetch: func() (string, error) {
		r.fetches++
		if during != nil {
			during()
		}
		return "fresh", nil
	}}
}

// through is pollThrough with an accept that marks what it accepted.
func (r *lockRig) through(read pollRead) (string, error) {
	return pollThrough(r.on, read, func(s string) (string, error) { return "accepted " + s, nil })
}

// holdLock writes another reader's lock holding text, made ago before the rig's clock.
func (r *lockRig) holdLock(text string, ago time.Duration) {
	r.t.Helper()
	if err := os.MkdirAll(r.on.c.dir, 0o700); err != nil {
		r.t.Fatal(err)
	}
	if err := os.WriteFile(r.lk, []byte(text), 0o644); err != nil {
		r.t.Fatal(err)
	}
	mt := r.clk.t.Add(-ago)
	if err := os.Chtimes(r.lk, mt, mt); err != nil {
		r.t.Fatal(err)
	}
}

// lockText is what the lock file holds, "" when it is gone.
func (r *lockRig) lockText() string {
	r.t.Helper()
	b, err := os.ReadFile(r.lk)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		r.t.Fatal(err)
	}
	return string(b)
}

// kept is the entry file as put wrote it, "" when there is none.
func (r *lockRig) kept() string {
	r.t.Helper()
	b, err := os.ReadFile(r.on.c.path(r.form, pollEntry))
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		r.t.Fatal(err)
	}
	return string(b)
}

// entryAt is the file put writes for out read at secs.
func (r *lockRig) entryAt(out string, secs float64) string {
	return `{"form": ` + r.form + `, "at": ` + Dumps(secs) + `, "out": ` + Dumps(out) + `}`
}

// If a waiter paused other than LOCK_PAUSE, or read gh for itself while a live holder still held
// the lock, or released that holder's lock, Python and Go waiters would not share one read: this
// goes red. The holder keeps its entry and lets go after the waiter's third pause.
func TestPollThroughWaitsOnALiveHolderThenTakesItsEntry(t *testing.T) {
	r := newLockRig(t)
	r.holdLock(strconv.Itoa(holderPid), 0)
	r.clk.onPause = func(n int) {
		if n == 3 {
			r.on.c.put(r.form, "the holder's", epochSeconds(r.clk.t))
			r.on.c.release(r.lk, holderPid)
		}
	}
	got, err := r.through(r.read(nil))
	if err != nil || got != "accepted the holder's" || r.fetches != 0 {
		t.Errorf("through = %q, %v after %d fetches; want the holder's entry and no fetch", got, err, r.fetches)
	}
	if want := []time.Duration{pyLockPause, pyLockPause, pyLockPause}; !slices.Equal(r.clk.pauses, want) {
		t.Errorf("through paused %v; want %v", r.clk.pauses, want)
	}
}

// If a dead holder's lock, one with no pid yet, or one held past the max age were left in place,
// every later reader would wait out its max age for an entry no one writes; if a younger live one
// were broken, two readers would both read gh: this goes red. While it reads, the taker's lock
// holds its own pid, and once it is done the lock is gone.
func TestPollThroughTakesOverADeadOrStaleLock(t *testing.T) {
	for _, row := range []struct {
		name   string
		text   string
		ago    time.Duration
		pauses int
	}{
		{"a dead pid", "4243", 0, 0},
		{"a live pid made the max age ago", strconv.Itoa(holderPid), 10 * time.Second, 0},
		{"a live pid that reaches the max age after two pauses", strconv.Itoa(holderPid), 9925 * time.Millisecond, 2},
		{"no pid yet, made the max age ago", "", 10 * time.Second, 0},
	} {
		r := newLockRig(t)
		r.holdLock(row.text, row.ago)
		var during string
		got, err := r.through(r.read(func() { during = r.lockText() }))
		if err != nil || got != "accepted fresh" || r.fetches != 1 {
			t.Errorf("%s: through = %q, %v after %d fetches; want one fresh read", row.name, got, err, r.fetches)
		}
		if len(r.clk.pauses) != row.pauses {
			t.Errorf("%s: through paused %d times; want %d", row.name, len(r.clk.pauses), row.pauses)
		}
		if during != strconv.Itoa(lockPid) || r.lockText() != "" {
			t.Errorf("%s: the lock held %q during the read and %q after; want %d, then none", row.name, during, r.lockText(), lockPid)
		}
	}
}

// If a waiter whose holder never lets go waited past its max age, or broke that lock as it gave up,
// a hung reader would stall its waiters or lose its own lock: this goes red. The lock's time is in
// the future, so it is never stale, and the waiter reads gh for itself once 1 s has passed.
func TestPollThroughReadsForItselfOnceItWaitedItsMaxAge(t *testing.T) {
	r := newLockRig(t)
	r.on.maxAge = 1
	r.holdLock(strconv.Itoa(holderPid), -time.Hour)
	got, err := r.through(r.read(nil))
	if err != nil || got != "accepted fresh" || r.fetches != 1 {
		t.Errorf("through = %q, %v after %d fetches; want one fresh read", got, err, r.fetches)
	}
	if len(r.clk.pauses) != 20 || r.lockText() != strconv.Itoa(holderPid) {
		t.Errorf("through paused %d times and left the lock %q; want 20 and the holder's", len(r.clk.pauses), r.lockText())
	}
}

// If a read were stamped with when it ended, a read slower than the max age would be kept as young
// and other readers would take output older than they asked for: this goes red. The read takes
// 15 s, so the next reader, with a max age of 10, reads gh again.
func TestPollThroughKeepsASlowReadWithItsStartTime(t *testing.T) {
	r := newLockRig(t)
	start := epochSeconds(r.clk.t)
	if _, err := r.through(r.read(func() { r.clk.t = r.clk.t.Add(15 * time.Second) })); err != nil {
		t.Fatal(err)
	}
	if want := r.entryAt("fresh", start); r.kept() != want {
		t.Errorf("through kept %s; want %s", r.kept(), want)
	}
	if _, err := r.through(r.read(nil)); err != nil || r.fetches != 2 {
		t.Errorf("the next reader, 15 s after the slow read began, made %d fetches in all, %v; want 2", r.fetches, err)
	}
}

// If a read that accept refused, or that failed, were kept, the next reader would take output its
// caller could not use; if the lock stayed, every waiter would wait out its max age: this goes red.
func TestPollThroughKeepsNoReadAcceptOrFetchRefused(t *testing.T) {
	refused := errors.New("unreadable answer")
	r := newLockRig(t)
	_, err := pollThrough(r.on, r.read(nil), func(string) (int, error) { return 0, refused })
	if !errors.Is(err, refused) || r.kept() != "" || r.lockText() != "" {
		t.Errorf("a refused read: through = %v, kept %q, lock %q; want accept's error, nothing kept, no lock", err, r.kept(), r.lockText())
	}
	r = newLockRig(t)
	failed := errors.New("gh: exit 1")
	_, err = r.through(pollRead{argv: pollKeyRows[0].argv, fetch: func() (string, error) { return "", failed }})
	if !errors.Is(err, failed) || r.kept() != "" || r.lockText() != "" {
		t.Errorf("a failed read: through = %v, kept %q, lock %q; want fetch's error, nothing kept, no lock", err, r.kept(), r.lockText())
	}
}

// If a reader released a lock by its path alone, a slow reader whose lock was broken as stale
// would remove the lock of the reader that took it next: this goes red.
func TestPollThroughReleasesOnlyItsOwnLock(t *testing.T) {
	r := newLockRig(t)
	if _, err := r.through(r.read(func() { r.holdLock("4244", 0) })); err != nil {
		t.Fatal(err)
	}
	if r.lockText() != "4244" {
		t.Errorf("after the read, the lock holds %q; want the next taker's 4244", r.lockText())
	}
}

// If a reader that took the lock read gh without looking again, it would read what another reader
// kept between its first look and its lock; if a lock that cannot be made, or a folder, stopped the
// read, a full disk would fail every poll: this goes red.
func TestPollThroughLooksAgainOnceItHoldsTheLock(t *testing.T) {
	r := newLockRig(t)
	r.st.beforeCreate = func() {
		r.on.c.put(r.form, "kept between", epochSeconds(r.clk.t))
		r.st.beforeCreate = nil
	}
	got, err := r.through(r.read(nil))
	if err != nil || got != "accepted kept between" || r.fetches != 0 || r.lockText() != "" {
		t.Errorf("through = %q, %v after %d fetches, lock %q; want the entry, no fetch, no lock", got, err, r.fetches, r.lockText())
	}

	r = newLockRig(t)
	r.st.createErr = fs.ErrPermission
	got, err = r.through(r.read(nil))
	if err != nil || got != "accepted fresh" || r.kept() != r.entryAt("fresh", epochSeconds(r.clk.t)) {
		t.Errorf("no lock: through = %q, %v, kept %q; want a fresh read, kept", got, err, r.kept())
	}

	r = newLockRig(t)
	r.st.mkdirErr = fs.ErrPermission
	got, err = r.through(r.read(nil))
	if err != nil || got != "accepted fresh" || r.fetches != 1 {
		t.Errorf("no folder: through = %q, %v after %d fetches; want one fresh read", got, err, r.fetches)
	}
	if _, err := os.Stat(r.on.c.dir); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("no folder: %s is there, %v; want nothing made", r.on.c.dir, err)
	}
}

// If newPollOn cached with SWARM_POLL_CACHE_SECONDS 0, unset or not digits, or with no folder, a
// call that never asked would read or write entries; if it did not cache with both set, ci_gate's
// pages would read gh on every poll: this goes red. With the cache on, a kept read stands in for
// gh's; with it off, the entry is left as it was.
func TestNewPollOnCachesOnlyWithBothSettings(t *testing.T) {
	t.Setenv(pollAgeVar, "")
	dir := filepath.Join(t.TempDir(), "poll-cache")
	c := &pollCache{st: store.Files{}, dir: dir, now: time.Now}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	form := pollForm(pollKeyRows[0].argv, "")
	c.put(form, "kept", epochSeconds(time.Now()))
	keptBytes, err := os.ReadFile(c.path(form, pollEntry))
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range []struct {
		name, dir, secs string
		set, want       bool
	}{
		{"both set", dir, "30", true, true},
		{"seconds with a leading 0", dir, "05", true, true},
		{"seconds 0", dir, "0", true, false},
		{"seconds empty", dir, "", true, false},
		{"seconds unset", dir, "", false, false},
		{"seconds not digits", dir, "5s", true, false},
		{"seconds signed", dir, "+5", true, false},
		{"no folder", "", "30", true, false},
	} {
		t.Setenv(pollCacheVar, row.dir)
		t.Setenv(pollSecondsVar, row.secs)
		if !row.set {
			if err := os.Unsetenv(pollSecondsVar); err != nil {
				t.Fatal(err)
			}
		}
		calls := 0
		read := pollRead{argv: pollKeyRows[0].argv, fetch: func() (string, error) { calls++; return "from gh", nil }}
		on := newPollOn(store.Files{}, lockPid, func(time.Duration) { t.Fatalf("%s: paused with no lock held", row.name) })
		got, err := pollThrough(on, read, func(s string) (string, error) { return s, nil })
		want, wantCalls := "from gh", 1
		if row.want {
			want, wantCalls = "kept", 0
		}
		if err != nil || got != want || calls != wantCalls {
			t.Errorf("%s: through = %q, %v after %d gh calls; want %q after %d", row.name, got, err, calls, want, wantCalls)
		}
		if b, err := os.ReadFile(c.path(form, pollEntry)); err != nil || string(b) != string(keptBytes) {
			t.Errorf("%s: the entry holds %s, %v after the read; want it as it was, %s", row.name, b, err, keptBytes)
		}
		if row.want && (on.pid != lockPid || on.maxAge <= 0) {
			t.Errorf("%s: newPollOn's pid %d and max age %d; want %d and the setting", row.name, on.pid, on.maxAge, lockPid)
		}
	}
}
