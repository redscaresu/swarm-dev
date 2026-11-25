package merge

import (
	"errors"
	"io/fs"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// The poll cache's lock and its read through the cache, as bin/lib/poll_cache.py's lock, owner,
// release, stale, holder and through have them. Two readers that miss together make one read: the
// first to create <key>.lock, holding its pid, reads, and the others wait for its entry. The lock
// file and its protocol are Python's, so a Go reader and a Python one wait on each other. Nothing
// runs this Go yet; poll_cache.py still takes the lock.

const (
	// pollCacheVar names the cache's folder, <project>/.swarm/poll-cache. ci_gate's pages caches
	// only when it is set.
	pollCacheVar = "SWARM_POLL_CACHE"
	// pollSecondsVar gives the oldest entry a reader takes, in whole seconds; 0 or unset is off.
	pollSecondsVar = "SWARM_POLL_CACHE_SECONDS"
	// pollLock ends a lock's name, after its key.
	pollLock = ".lock"
	// pollLockPause is poll_cache.py's LOCK_PAUSE: how long a waiter pauses between looks at another
	// reader's lock.
	pollLockPause = 50 * time.Millisecond
)

// pollOn is a read's cache, poll_cache.py's on: the folder's cache and the oldest entry a reader
// takes, in whole seconds. pause is how a waiter sleeps between looks at another reader's lock, and
// pid is the pid this process writes in a lock it takes. The zero value is off.
type pollOn struct {
	c      *pollCache
	maxAge int
	pause  func(time.Duration)
	pid    int
}

// pollRead is one read through the cache: gh's argv and its output filter, "" for none, which make
// the entry's form, and fetch, which reads it from gh.
type pollRead struct {
	argv  []string
	filt  string
	fetch func() (string, error)
}

// newPollOn is the cache the call's environment asks for, as poll_cache.py's settings() gives it:
// on when pollCacheVar names a folder and pollSecondsVar is ASCII digits for a number above 0, off
// otherwise. Python's isdigit also takes other scripts' digits, which no caller sets; digits past
// an int's range are off here. pid is the process's own, which a rules package may not read, and
// pause must sleep unscaled, as Python's time.sleep does: the wiring passes both.
func newPollOn(st iface.Store, pid int, pause func(time.Duration)) pollOn {
	dir, secs := os.Getenv(pollCacheVar), os.Getenv(pollSecondsVar)
	for i := 0; i < len(secs); i++ {
		if !isDigit(secs[i]) {
			return pollOn{}
		}
	}
	age, err := strconv.Atoi(secs)
	if dir == "" || err != nil || age <= 0 {
		return pollOn{}
	}
	return pollOn{c: newPollCache(st, dir), maxAge: age, pause: pause, pid: pid}
}

// pollThrough returns accept of gh's output for r, as poll_cache.py's through does. With on off,
// r.fetch reads it. With on on, an entry of r's form under on.maxAge old stands in for the read, and
// a read accept returned no error for is kept, stamped with when it started, so a read slower than
// the max age is kept as old as it is. A miss takes the form's lock first, or waits in
// pollLockPause steps for the reader that holds it to keep its entry. A lock whose pid has exited,
// or one on.maxAge old or more, is released and taken. After waiting on.maxAge, or when the lock
// cannot be made, the reader reads for itself. Only the taker releases its lock. An error from fetch
// or accept is returned, and nothing is kept then.
func pollThrough[T any](on pollOn, r pollRead, accept func(string) (T, error)) (T, error) {
	if on.c == nil {
		return fetchAccept(r, accept)
	}
	c := on.c
	form := pollForm(r.argv, r.filt)
	lk := c.path(form, pollLock)
	if c.st.MkdirAll(c.dir) != nil {
		return fetchAccept(r, accept)
	}
	held, end := lockOther, epochSeconds(c.now())+float64(on.maxAge)
	for {
		if out, ok := c.entry(form, on.maxAge); ok {
			return accept(out)
		}
		held = c.lock(lk, on.pid)
		if held != lockOther || epochSeconds(c.now()) >= end {
			break
		}
		state, pid := c.holder(lk)
		if state == holderDead || (state == holderAlive && c.stale(lk, on.maxAge)) {
			// Killed before it wrote or let go, or held past the max age (a reader stopped, hung, or
			// killed before it wrote its pid): the next pass takes the lock (one waiter does).
			c.release(lk, pid)
		} else if state == holderAlive {
			on.pause(pollLockPause)
		}
	}
	if held == lockHeld {
		defer c.release(lk, on.pid)
		// Another reader may have written and let go between the look above and the lock.
		if out, ok := c.entry(form, on.maxAge); ok {
			return accept(out)
		}
	}
	at := epochSeconds(c.now())
	out, err := r.fetch()
	if err != nil {
		var none T
		return none, err
	}
	got, err := accept(out)
	if err != nil {
		return got, err
	}
	c.put(form, out, at)
	return got, nil
}

// fetchAccept is accept of r.fetch's output, read with no cache.
func fetchAccept[T any](r pollRead, accept func(string) (T, error)) (T, error) {
	out, err := r.fetch()
	if err != nil {
		var none T
		return none, err
	}
	return accept(out)
}

// lockTake is what a try at a lock gave, poll_cache.py's lock's True, False and None.
type lockTake int

const (
	lockHeld   lockTake = iota // this process now holds the lock
	lockOther                  // another reader holds it
	lockFailed                 // it cannot be made, so the read goes to gh uncached
)

// lock makes the lock at path holding pid, as poll_cache.py's lock does: an exclusive create, with
// the pid written after it. A create that fails because path is there gives lockOther; any other
// failure, a full disk's failed write among them, gives lockFailed, and leaves no lock.
func (c *pollCache) lock(path string, pid int) lockTake {
	err := c.st.CreateExclusive(path, []byte(strconv.Itoa(pid)))
	if err == nil {
		return lockHeld
	}
	if errors.Is(err, fs.ErrExist) {
		return lockOther
	}
	return lockFailed
}

// owner returns the pid in the lock at path and true, as poll_cache.py's owner does: false when it
// is gone, and 0 while it is still being written, or holds anything but an int with spaces around
// it. Python's int also reads underscores and other scripts' digits, which no lock holds.
func (c *pollCache) owner(path string) (int, bool) {
	data, err := c.st.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return 0, false
	}
	if err != nil {
		return 0, true
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return 0, true
	}
	return pid, true
}

// release removes the lock at path while it still names pid, as poll_cache.py's release does, so
// a reader never removes a lock that another took after the one it looked at.
func (c *pollCache) release(path string, pid int) {
	if got, ok := c.owner(path); ok && got == pid {
		c.remove(path)
	}
}

// stale reports whether the lock at path was made maxAge seconds ago or more, as poll_cache.py's
// stale does: false when its stat fails.
func (c *pollCache) stale(path string, maxAge int) bool {
	info, err := c.st.Stat(path)
	if err != nil {
		return false
	}
	return epochSeconds(c.now())-epochSeconds(info.ModTime()) >= float64(maxAge)
}

// holderState is a lock's state, poll_cache.py's holder's "gone", "dead" and "alive".
type holderState int

const (
	holderGone  holderState = iota // no lock
	holderDead                     // its pid has exited
	holderAlive                    // its pid runs, or is still being written
)

// holder returns the lock's state and its pid, as poll_cache.py's holder does. A pid of 0, still
// being written, is alive. A pid below 0 is dead here, where Python's os.kill signals the process
// group it names; no lock holds one.
func (c *pollCache) holder(path string) (holderState, int) {
	pid, ok := c.owner(path)
	if !ok {
		return holderGone, 0
	}
	if pid != 0 && !c.st.Alive(pid) {
		return holderDead, pid
	}
	return holderAlive, pid
}
